# frozen_string_literal: true

require "uri"

module ProviderCompiler

  class RubyProjection
    def initialize(blueprint)
      @blueprint = blueprint
    end

    def render
      provider = @blueprint.fetch("provider").fetch("name")
      class_name = "#{Util.camel(provider)}Service"
      validate_class_name!(class_name)
      endpoints = @blueprint.fetch("endpoints").each_with_object({}) do |endpoint, result|
        result[endpoint.fetch("operation_id").to_s] = { "method" => endpoint.fetch("method"), "path" => endpoint.fetch("path"), "canonical" => endpoint["canonical"], "success_statuses" => Array(endpoint["success_statuses"]) }
      end
      status_map = @blueprint.fetch("statuses").each_with_object({}) { |item, result| result[item.fetch("provider_value")] = item.fetch("canonical_value") }
      extras = @blueprint.fetch("extra_operations").each_with_object({}) { |item, result| result[item.fetch("operation_id").to_s] = { "method" => item.fetch("method"), "path" => item.fetch("path") } }
      conditions = @blueprint.fetch("conditionals").map do |item|
        predicate = item.fetch("predicate")
        {
          "type" => predicate.split("==", 2).last.to_s.strip,
          "required" => Array(item.fetch("required")).map { |path| path.to_s.split(".").last }
        }
      end
      selected_auth = @blueprint.dig("auth", "selected")
      auth_scheme = Array(@blueprint.dig("auth", "schemes")).find { |scheme| scheme["name"] == selected_auth }
      auth_strategy = auth_scheme && auth_scheme["strategy"]
      supported_auth = auth_strategy && ((auth_strategy["kind"] == "api_key" && %w[header query].include?(auth_strategy["transport"])) || (auth_strategy["kind"] == "bearer" && auth_strategy["transport"] == "header"))
      raise Error, "resolved Blueprint has no supported authentication strategy" unless supported_auth
      sandbox = @blueprint.fetch("servers").find { |server| server["environment"] == "sandbox" } || @blueprint.fetch("servers").first
      base_url = sandbox && sandbox["url"]
      raise Error, "resolved Blueprint has no server URL" if Util.blank?(base_url)
      validate_base_url!(base_url)
      validate_patterns!
      base_url_env = "#{Util.slug(provider).upcase}_BASE_URL"
      status_parameter = endpoint_path("fetch_status").to_s[/\{([^}]+)\}/, 1] || "id"
      webhook_id_field = @blueprint.dig("webhook", "identifier_field") || "id"
      create_success_statuses = success_statuses("create_request")
      status_success_statuses = success_statuses("fetch_status")
      profile = @blueprint.fetch("base_service_profile")
      failure_contract = profile.fetch("failure_contract", {})
      erb = ERB.new(TEMPLATE, trim_mode: "-")
      erb.result_with_hash(
        provider: provider,
        class_name: class_name,
        endpoints: ruby_literal(endpoints),
        field_mappings: ruby_literal(@blueprint.fetch("field_mappings")),
        status_map: ruby_literal(status_map),
        errors: ruby_literal(@blueprint.fetch("errors")),
        extras: ruby_literal(extras),
        money: ruby_literal(@blueprint.fetch("money")),
        webhook: ruby_literal(@blueprint.fetch("webhook")),
        constraints: ruby_literal(@blueprint.fetch("constraints")),
        idempotency: ruby_literal(@blueprint.fetch("idempotency")),
        conditions: ruby_literal(conditions),
        auth_strategy: ruby_literal(auth_strategy),
        base_url: base_url,
        base_url_env: base_url_env,
        status_parameter: status_parameter,
        webhook_id_field: webhook_id_field,
        callback_actions: ruby_literal(@blueprint.dig("base_service_profile", "callback_actions") || {}),
        failure_arguments: ruby_literal(Array(failure_contract.fetch("arguments", ["message"]))),
        call_super_conditions: profile.dig("check_conditions", "call_super") == true,
        validation_failure_status: ruby_literal(failure_contract.fetch("validation_status", 422)),
        validation_failure_code: ruby_literal(failure_contract.fetch("validation_code", "validation_error")),
        create_method: endpoint_method("create_request"),
        status_method: endpoint_method("fetch_status"),
        create_path: endpoint_path("create_request"),
        status_path: endpoint_path("fetch_status"),
        create_success_statuses: ruby_literal(create_success_statuses),
        status_success_statuses: ruby_literal(status_success_statuses)
      )
    end

    private

    def validate_class_name!(class_name)
      return if class_name.match?(/\A[A-Z][A-Za-z0-9_]*\z/)

      raise Error, "provider title cannot produce a safe Ruby service class name"
    end

    def validate_base_url!(base_url)
      uri = URI.parse(base_url.to_s)
      return if %w[http https].include?(uri.scheme) && !base_url.to_s.match?(/[\r\n]/)

      raise Error, "provider server URL must be an HTTP(S) URL without control characters"
    rescue URI::InvalidURIError
      raise Error, "provider server URL is invalid"
    end

    def validate_patterns!
      Array(@blueprint["constraints"]).each do |constraint|
        pattern = constraint["pattern"]
        next if pattern.nil?
        raise Error, "provider regex is too large" if pattern.to_s.length > 1024
        raise Error, "provider regex has unsafe nested quantifiers" if pattern.to_s.match?(/\([^)]*[+*][^)]*\)[+*]/)

        Regexp.new(pattern.to_s)
      rescue RegexpError, ArgumentError => e
        raise Error, "provider regex is invalid: #{e.message}"
      end
    end

    def endpoint_path(role)
      endpoint = @blueprint.fetch("endpoints").find { |item| item["canonical"] == role }
      endpoint ? endpoint.fetch("path") : (raise Error, "resolved Blueprint has no #{role} endpoint")
    end

    def endpoint_method(role)
      endpoint = @blueprint.fetch("endpoints").find { |item| item["canonical"] == role }
      endpoint ? endpoint.fetch("method") : (raise Error, "resolved Blueprint has no #{role} endpoint")
    end

    def success_statuses(role)
      endpoint = @blueprint.fetch("endpoints").find { |item| item["canonical"] == role }
      statuses = Array(endpoint && endpoint["success_statuses"]).map(&:to_s).reject(&:empty?)
      raise Error, "resolved Blueprint has no documented success status for #{role}" if statuses.empty?

      statuses
    end

    def ruby_literal(value)
      case value
      when Hash
        "{#{value.keys.sort_by(&:to_s).map { |key| "#{key.inspect} => #{ruby_literal(value[key])}" }.join(", ")}}"
      when Array
        "[#{value.map { |item| ruby_literal(item) }.join(", ")}]"
      when String
        value.inspect
      when true, false, nil, Numeric
        value.inspect
      else
        value.to_s.inspect
      end
    end

    TEMPLATE = <<~'RUBY'
      # frozen_string_literal: true

      require "bigdecimal"
      require "json"
      require "openssl"
      require "securerandom"
      require "uri"

      module Provider
        class <%= class_name %> < BaseService
          PROVIDER_NAME = <%= provider.inspect %>.freeze
          BASE_URL = ENV.fetch(<%= base_url_env.inspect %>, <%= base_url.inspect %>).sub(%r{/$}, "").freeze
          AUTH_STRATEGY = <%= auth_strategy %>.freeze
          CREATE_METHOD = <%= create_method.inspect %>.freeze
          STATUS_METHOD = <%= status_method.inspect %>.freeze
          STATUS_PARAMETER = <%= status_parameter.inspect %>.freeze
          WEBHOOK_ID_FIELD = <%= webhook_id_field.inspect %>.freeze
          CALLBACK_ACTIONS = <%= callback_actions %>.freeze
          ENDPOINTS = <%= endpoints %>.freeze
          FIELD_MAPPINGS = <%= field_mappings %>.freeze
          STATUS_MAP = <%= status_map %>.freeze
          ERROR_MODEL = <%= errors %>.freeze
          EXTRA_OPERATIONS = <%= extras %>.freeze
          MONEY = <%= money %>.freeze
          CONSTRAINTS = <%= constraints %>.freeze
          WEBHOOK = <%= webhook %>.freeze
          IDEMPOTENCY = <%= idempotency %>.freeze
          CONDITIONALS = <%= conditions %>.freeze
          CREATE_SUCCESS_STATUSES = <%= create_success_statuses %>.freeze
          STATUS_SUCCESS_STATUSES = <%= status_success_statuses %>.freeze
          CALL_SUPER_CONDITIONS = <%= call_super_conditions.inspect %>
          FAILURE_ARGUMENTS = <%= failure_arguments %>.freeze
          VALIDATION_FAILURE_STATUS = <%= validation_failure_status %>
          VALIDATION_FAILURE_CODE = <%= validation_failure_code %>

          def initialize(api_key:, webhook_secret: nil, client: nil)
            @api_key = api_key
            @webhook_secret = webhook_secret
            @client = client
            @idempotency_keys = {}
          end

          def check_conditions(operation, request_method)
            if CALL_SUPER_CONDITIONS
              base_result = super(operation, request_method)
              return base_result if failed_result?(base_result)
            end

            return success if request_method.to_s != "create"

            errors = validate_constraints(operation)
            errors.concat(validate_conditionals(operation))
            errors.empty? ? success : host_failure(errors.join("; "), status: VALIDATION_FAILURE_STATUS, code: VALIDATION_FAILURE_CODE)
          end

          def build_create_request(operation, request_method = "create")
            raise ArgumentError, "unsupported request_method: #{request_method}" unless request_method.to_s == "create"
            condition_result = check_conditions(operation, request_method)
            raise ArgumentError, condition_error(condition_result) if failed_result?(condition_result)

            body = build_provider_body(operation)
            headers, query = authentication
            key = read(operation, :idempotency_key)
            if IDEMPOTENCY.dig("adapter_policy", "send_header") == "always" || (IDEMPOTENCY.dig("adapter_policy", "send_header") == "if_available" && !blank?(key))
              if IDEMPOTENCY.fetch("header")
                stable_key = key || @idempotency_keys[read(operation, :external_id).to_s] || SecureRandom.uuid
                @idempotency_keys[read(operation, :external_id).to_s] = stable_key unless key
                headers[IDEMPOTENCY.fetch("header")] = stable_key
              end
            end
            path = <%= create_path.inspect %>
            { "method" => CREATE_METHOD, "path" => path, "url" => "#{BASE_URL}#{path}", "headers" => headers, "query" => query, "body" => body }
          end

          def create_request(operation, request_method = "create")
            request = build_create_request(operation, request_method)
            return request unless @client

            response = dispatch_or_failure(request)
            return response if compiler_failure?(response)

            handle_response(response, expected_success: CREATE_SUCCESS_STATUSES)
          end

          def fetch_status(operation)
            id = read(operation, :provider_operation_id) || read(operation, :id)
            return host_failure("provider operation id is required", code: "missing_provider_operation_id") if blank?(id)
            path = <%= status_path.inspect %>.sub("{#{STATUS_PARAMETER}}", escape_path_segment(id))
            headers, query = authentication
            request = { "method" => STATUS_METHOD, "path" => path, "url" => "#{BASE_URL}#{path}", "headers" => headers, "query" => query }
            return request unless @client

            response = dispatch_or_failure(request)
            return response if compiler_failure?(response)

            handle_response(response, expected_success: STATUS_SUCCESS_STATUSES)
          end

          def process_callback(payload)
            return host_failure("provider has no webhook; polling-only integration", code: "polling_only") if WEBHOOK["mode"] == "polling_only"

            raw_body = read(payload, :raw_body)
            signature = read(payload, :signature) || read(read(payload, :headers), WEBHOOK.dig("signature", "header"))
            return host_failure("raw webhook body is required", code: "missing_raw_body") if blank?(raw_body)
            return host_failure("webhook signature is required", code: "missing_webhook_signature") if blank?(signature)
            return host_failure("invalid webhook signature", code: "invalid_webhook_signature") unless verify_webhook_signature(raw_body, signature)

            event = read(payload, :event)
            body = parse_json(raw_body)
            body = body.is_a?(Hash) ? body : {}
            provider_status = (read(payload, :status) || body["status"]).to_s
            event = read(payload, :event) || body["event"]
            event_status = event.to_s.split(".").last
            if !blank?(provider_status) && !blank?(event_status) && provider_status.casecmp?(event_status) == false
              return host_failure("webhook event/status contradiction", code: "webhook_contradiction")
            end
            canonical = WEBHOOK.fetch("events", {})[event.to_s]
            return host_failure("unknown webhook event", code: "unknown_webhook_event") if canonical.nil? || canonical == "UNKNOWN"

            result = { "ok" => true, "provider_status" => provider_status, "status" => canonical, "event" => event, "external_id" => read(payload, :external_id) || body["external_id"], "provider_operation_id" => read(payload, WEBHOOK_ID_FIELD) || body[WEBHOOK_ID_FIELD] }
            action_result = bind_callback_action(canonical, result["provider_operation_id"] || result["external_id"] || result)
            return action_result.merge("provider_status" => provider_status, "status" => canonical, "event" => event) unless action_result["ok"] != false

            result.merge(action_result)
          end

          def verify_webhook_signature(raw_body, signature)
            return false if @webhook_secret.nil?

            digest = OpenSSL::HMAC.digest(OpenSSL::Digest.new("SHA256"), @webhook_secret, raw_body.to_s)
            expected = WEBHOOK.dig("signature", "encoding") == "base64" ? [digest].pack("m0") : digest.unpack1("H*")
            secure_compare(expected, signature.to_s)
          end

          def provider_amount_to_host(value)
            conversion = MONEY.fetch("response_conversion")
            amount = decimal_amount(value)
            amount * BigDecimal((conversion["factor_decimal"] || conversion.fetch("factor")).to_s)
          end

          def host_amount_to_provider(value)
            convert_host_amount(value)
          end

          def host_failure(message, status: VALIDATION_FAILURE_STATUS, code: "runtime_error")
            values = { "status" => status, "code" => code, "message" => message }
            result = failure(*FAILURE_ARGUMENTS.map { |argument| values.fetch(argument.to_s) })
            result.is_a?(Hash) ? result.merge("provider_compiler_failure" => true) : result
          end

          private

          def failed_result?(result)
            return result["ok"] == false if result.is_a?(Hash) && result.key?("ok")
            return result.failed? if result.respond_to?(:failed?)
            return !result.ok? if result.respond_to?(:ok?)

            false
          end

          def condition_error(result)
            read(result, :error) || read(result, :message) || "BaseService rejected operation"
          end

          def compiler_failure?(result)
            result.is_a?(Hash) && result["provider_compiler_failure"] == true
          end

          def convert_host_amount(value)
            conversion = MONEY.fetch("request_conversion")
            converted = decimal_amount(value) * BigDecimal((conversion["factor_decimal"] || conversion.fetch("factor")).to_s)
            return value if conversion["direction"] == "same_unit"
            if conversion["direction"] == "major_to_minor"
              raise ArgumentError, "money conversion did not produce an exact provider unit" unless converted.frac.zero?

              converted.to_i
            else
              converted
            end
          end

          def decimal_amount(value)
            decimal = BigDecimal(value.to_s)
            raise ArgumentError, "money amount must be finite" unless decimal.finite?

            decimal
          rescue ArgumentError
            raise ArgumentError, "money amount must be numeric"
          end

          def bind_callback_action(canonical, operation_reference)
            action = CALLBACK_ACTIONS[canonical]
            return { "action" => "none", "terminal" => false } if action.nil? && canonical == "in_progress"
            return host_failure("callback action binding is unresolved", code: "unresolved_callback_action") if action.nil?
            return host_failure("callback action is not available on BaseService", code: "missing_callback_action") unless respond_to?(action)

            { "action" => action, "terminal" => true, "action_result" => public_send(action, operation_reference) }
          end

          def validate_constraints(operation)
            CONSTRAINTS.filter_map do |constraint|
              field = constraint.fetch("path").sub(/\Arequest\./, "")
              value = mapped_constraint_value(operation, constraint)
              numeric_invalid = if !value.nil? && (constraint["minimum"] || constraint["maximum"])
                                  begin
                                    BigDecimal(value.to_s)
                                    false
                                  rescue ArgumentError
                                    true
                                  end
                                end
              if numeric_invalid
                "#{field} must be numeric"
              elsif constraint["required"] && blank?(value)
                "#{field} is required"
              elsif !value.nil? && constraint["enum"] && !Array(constraint["enum"]).include?(value)
                "#{field} must be one of #{Array(constraint["enum"]).join(", ")}"
              elsif !value.nil? && constraint["minimum"] && BigDecimal(value.to_s) < BigDecimal((constraint["host_minimum"] || constraint["minimum"]).to_s)
                "#{field} is below minimum #{constraint["host_minimum"] || constraint["minimum"]}"
              elsif !value.nil? && constraint["maximum"] && BigDecimal(value.to_s) > BigDecimal(constraint["maximum"].to_s)
                "#{field} exceeds maximum #{constraint["maximum"]}"
              elsif !value.nil? && constraint["minLength"] && value.to_s.length < constraint["minLength"].to_i
                "#{field} is shorter than #{constraint["minLength"]}"
              elsif !value.nil? && constraint["maxLength"] && value.to_s.length > constraint["maxLength"].to_i
                "#{field} is longer than #{constraint["maxLength"]}"
              elsif !value.nil? && constraint["pattern"] && value.to_s !~ Regexp.new(constraint["pattern"])
                "#{field} does not match the provider pattern"
              end
            end
          end

          def validate_conditionals(operation)
            recipient = read(operation, :recipient) || {}
            type = read(recipient, :type).to_s
            CONDITIONALS.filter_map do |condition|
              next unless type == condition.fetch("type")

              missing = condition.fetch("required").filter_map do |path|
                field = path.to_s.split(".").last
                field unless !blank?(read(recipient, field))
              end
              missing.empty? ? nil : "#{missing.join(", ")} is required when type=#{type}"
            end
          end

          def read_path(object, path)
            path.to_s.split(".").reduce(object) { |current, key| read(current, key) }
          end

          def authentication
            case AUTH_STRATEGY.fetch("kind")
            when "api_key"
              AUTH_STRATEGY.fetch("transport") == "query" ? [{}, { AUTH_STRATEGY.fetch("name") => @api_key }] : [{ AUTH_STRATEGY.fetch("name") => @api_key }, {}]
            when "bearer"
              [{ AUTH_STRATEGY.fetch("name") => "Bearer #{@api_key}" }, {}]
            else
              raise ArgumentError, "unsupported authentication strategy"
            end
          end

          def dispatch_or_failure(request)
            dispatch(request)
          rescue StandardError => e
            host_failure("provider transport error: #{e.class}: #{e.message}", status: 502, code: "transport_error")
          end

          def dispatch(request)
            if @client.respond_to?(:request)
              @client.request(request.fetch("method"), request.fetch("url"), request.fetch("headers"), request.fetch("body", nil), request.fetch("query", {}))
            elsif request.fetch("method") == "GET" && @client.respond_to?(:get)
              @client.get(with_query(request.fetch("url"), request.fetch("query", {})), request.fetch("headers"))
            elsif request.fetch("method") == "POST" && @client.respond_to?(:post)
              @client.post(with_query(request.fetch("url"), request.fetch("query", {})), request.fetch("headers"), request.fetch("body"))
            else
              raise ArgumentError, "client does not support #{request.fetch("method")}"
            end
          end

          def with_query(url, query)
            return url if query.nil? || query.empty?

            separator = url.include?("?") ? "&" : "?"
            "#{url}#{separator}#{URI.encode_www_form(query)}"
          end

          def escape_path_segment(value)
            value.to_s.gsub(/[^A-Za-z0-9._~-]/) { |character| "%%%02X" % character.ord }
          end

          def handle_response(response, expected_success:)
            body_present = (response.is_a?(Hash) && (response.key?("body") || response.key?(:body))) || (!response.is_a?(Hash) && response.respond_to?(:body))
            http_status = read(response, :http_status) || read(response, :status_code) || (body_present ? read(response, :status) : nil)
            body = if body_present
                     read(response, :body)
                   elsif http_status && response.is_a?(Hash) && (response.keys.map(&:to_s) - %w[http_status status_code status headers]).empty?
                     nil
                   else
                     response
                   end
            raw_body = body
            body = parse_json(body) if body.is_a?(String)
            if http_status && !expected_success.map(&:to_s).include?(http_status.to_s)
              return provider_error(response, body, http_status)
            end

            return host_failure("provider response body is malformed JSON", status: 502, code: "invalid_provider_response") if body.nil? && raw_body.is_a?(String) && !raw_body.empty? && http_status
            return { "ok" => true, "http_status" => http_status.to_s, "response" => nil } if body.nil? && http_status
            return host_failure("provider response body is not an object", status: 502, code: "invalid_provider_response") unless body.is_a?(Hash)
            mapped = map_provider_response(body)
            provider_status = mapped["provider_status"].to_s
            canonical_status = STATUS_MAP.fetch(provider_status, "unknown")
            result = { "ok" => true, "provider_status" => provider_status, "status" => canonical_status, "response" => body }
            result["http_status"] = http_status.to_s if http_status
            mapped.each { |key, value| result[key] = value unless %w[provider_status status].include?(key) }
            result["error"] = read(body, :error) if read(body, :error)
            result["ok"] = false if canonical_status == "unknown"
            result["error"] ||= "unknown provider status" if canonical_status == "unknown"
            result
          end

          def build_provider_body(operation)
            body = {}
            mappings = FIELD_MAPPINGS.select { |mapping| mapping["direction"].to_s == "request" }
            mappings.each do |mapping|
              canonical_path = mapping.fetch("canonical_path").sub("operation.", "")
              provider_path = mapping.fetch("provider_path").sub("request.", "")
              value = read_path(operation, canonical_path)
              next if value.nil?

              value = host_amount_to_provider(value) if canonical_path == "amount"
              set_path(body, provider_path, value)
            end
            body
          end

          def map_provider_response(body)
            result = {}
            FIELD_MAPPINGS.select { |mapping| mapping["direction"].to_s == "response" }.each do |mapping|
              provider_path = mapping.fetch("provider_path").sub("response.", "")
              value = read_path(body, provider_path)
              next if value.nil?

              canonical_path = mapping.fetch("canonical_path").sub("operation.", "")
              if canonical_path == "amount"
                value = provider_amount_to_host(value)
              elsif canonical_path == "status"
                result["provider_status"] = value.to_s
              end
              result[canonical_path] = value
              result["provider_operation_id"] = value if canonical_path == "provider_operation_id"
            end
            result["provider_status"] ||= read(body, :status).to_s
            result
          end

          def set_path(object, path, value)
            keys = path.to_s.split(".")
            leaf = keys.pop
            target = keys.reduce(object) { |current, key| current[key] ||= {} }
            target[leaf] = value
          end

          def mapped_constraint_value(operation, constraint)
            provider_path = constraint.fetch("path")
            mapping = FIELD_MAPPINGS.find do |item|
              item["direction"].to_s == "request" && (item["provider_path"] == provider_path || provider_path.start_with?("#{item["provider_path"]}.") || item["provider_path"].start_with?("#{provider_path}."))
            end
            canonical_path = if mapping
                               suffix = if mapping["provider_path"] == provider_path || provider_path.start_with?("#{mapping["provider_path"]}.")
                                          provider_path.delete_prefix(mapping["provider_path"]).sub(/\A\./, "")
                                        else
                                          ""
                                        end
                               [mapping["canonical_path"].sub("operation.", ""), suffix].reject(&:empty?).join(".")
                             else
                               provider_path.sub("request.", "")
                             end
            read_path(operation, canonical_path)
          end

          def provider_error(response, body, http_status)
            error = body.is_a?(Hash) ? (read(body, :error) || body) : {}
            provider_code = if error.is_a?(Hash)
                              read(error, :code) || read(read(error, :error), :code)
                            end
            status_entry = ERROR_MODEL.find { |item| item["http_status"].to_s == http_status.to_s }
            entry = Array(status_entry && status_entry["provider_codes"]).find { |item| !provider_code.nil? && item["code"].to_s == provider_code.to_s }
            headers = read(response, :headers)
            retry_after = if headers.is_a?(Hash)
                            headers["Retry-After"] || headers["retry-after"] || headers["RETRY-AFTER"]
                          end
            { "ok" => false, "http_status" => http_status.to_s, "error" => error, "error_code" => provider_code, "error_category" => entry ? entry["category"] : (status_entry && status_entry["canonical_category"]) || "unknown_provider_error", "retryable" => entry ? entry["retryable"] : !!(status_entry && status_entry["retryable"]), "action" => entry ? entry["action"] : (status_entry && status_entry["retryable"] ? "retry_after" : "preserve_and_review"), "retry_after" => retry_after }
          end

          def parse_json(raw_body)
            JSON.parse(raw_body.to_s)
          rescue JSON::ParserError
            nil
          end

          def read(object, key)
            return nil unless object
            if object.is_a?(Hash)
              object[key] || object[key.to_s] || (object[key.to_sym] if key.respond_to?(:to_sym))
            elsif object.respond_to?(key)
              object.public_send(key)
            elsif object.respond_to?(:[])
              object[key] || object[key.to_s] || (object[key.to_sym] if key.respond_to?(:to_sym))
            end
          end

          def blank?(value)
            value.nil? || value.to_s.empty?
          end

          def secure_compare(left, right)
            return false unless left.bytesize == right.bytesize
            result = 0
            left.bytes.zip(right.bytes) { |a, b| result |= a ^ b }
            result.zero?
          end
        end
      end
    RUBY
  end

  class FixtureSynthesizer
    def initialize(blueprint, spec_document: nil, fallback_examples: {})
      @blueprint = blueprint
      @spec_document = spec_document || {}
      @fallback = Util.deep_dup(fallback_examples || {})
    end

    def build
      result = Util.deep_dup(@fallback)
      provenance = {}
      create_operation = provider_operation("create_request")
      status_operation = provider_operation("fetch_status")
      webhook_operation = provider_operation("process_callback")

      request_body = request_example(create_operation)
      if request_body
        host_operation = host_operation_from_provider(request_body)
        result["create_request"] = merge_missing({ "operation" => host_operation }, result["create_request"] || {})
        provenance["create_request"] = request_source(create_operation)
      end

      response_body = response_example(status_operation)
      if response_body
        result["fetch_status"] = merge_missing({ "response" => response_body }, result["fetch_status"] || {})
        provenance["fetch_status"] = response_source(status_operation)
      end

      callback_body = request_example(webhook_operation)
      if callback_body
        result["webhook"] = merge_missing({ "body" => callback_body }, result["webhook"] || {})
        result["process_callback"] = merge_missing({ "body" => callback_body }, result["process_callback"] || {})
        provenance["process_callback"] = request_source(webhook_operation)
      end

      result["fixture_provenance"] = provenance unless provenance.empty?
      result
    end

    private

    def provider_operation(role)
      endpoint = Array(@blueprint["endpoints"]).find { |item| item["canonical"] == role }
      return nil unless endpoint

      path = @spec_document.dig("paths", endpoint["path"])
      path && path[endpoint["method"].to_s.downcase]
    end

    def request_example(operation)
      return nil unless operation.is_a?(Hash)

      media = operation.dig("requestBody", "content", "application/json") || {}
      explicit = media.dig("examples")
      return explicit.values.first["value"] if explicit.is_a?(Hash) && explicit.values.first.is_a?(Hash) && explicit.values.first.key?("value")
      return media["example"] if media.key?("example")

      schema_example(media["schema"])
    end

    def response_example(operation)
      return nil unless operation.is_a?(Hash)

      statuses = Array(@blueprint.dig("endpoints").find { |item| item["canonical"] == "fetch_status" }&.fetch("success_statuses", []))
      response = statuses.map { |status| operation.dig("responses", status) }.compact.first
      response ||= operation.fetch("responses", {}).values.find { |item| item.is_a?(Hash) && item.dig("content", "application/json") }
      return nil unless response.is_a?(Hash)

      media = response.dig("content", "application/json") || {}
      explicit = media.dig("examples")
      return explicit.values.first["value"] if explicit.is_a?(Hash) && explicit.values.first.is_a?(Hash) && explicit.values.first.key?("value")
      return media["example"] if media.key?("example")

      preferred_status(schema_example(media["schema"]))
    end

    def request_source(operation)
      media = operation&.dig("requestBody", "content", "application/json") || {}
      return "SPEC_EXAMPLE" if media["example"] || media["examples"]

      schema_source(media["schema"])
    end

    def response_source(operation)
      statuses = Array(@blueprint.dig("endpoints").find { |item| item["canonical"] == "fetch_status" }&.fetch("success_statuses", []))
      response = statuses.map { |status| operation&.dig("responses", status) }.compact.first
      response ||= operation&.fetch("responses", {})&.values&.find { |item| item.is_a?(Hash) && item.dig("content", "application/json") }
      media = response&.dig("content", "application/json") || {}
      return "SPEC_EXAMPLE" if media["example"] || media["examples"]

      schema_source(media["schema"])
    end

    def schema_source(schema)
      return "SCHEMA_EXAMPLE" if schema_contains?(schema, "example") || schema_contains?(schema, "examples")
      return "SCHEMA_DEFAULT" if schema_contains?(schema, "default")
      return "ENUM" if schema_contains?(schema, "enum")

      "DETERMINISTIC_SCHEMA_SAMPLE"
    end

    def schema_contains?(schema, key)
      case schema
      when Hash
        return true if schema.key?(key)

        schema.any? { |_name, value| schema_contains?(value, key) }
      when Array
        schema.any? { |value| schema_contains?(value, key) }
      else
        false
      end
    end

    def preferred_status(value)
      return value unless value.is_a?(Hash)

      approved = Array(@blueprint["statuses"]).find { |item| item["canonical_value"] == "approved" }&.fetch("provider_value", nil)
      return value unless approved

      replace_status(value, approved)
    end

    def replace_status(value, provider_value)
      value.each_with_object({}) do |(key, item), result|
        result[key] = if key.to_s.match?(/\A(?:status|state|phase)\z/i)
                        provider_value
                      elsif item.is_a?(Hash)
                        replace_status(item, provider_value)
                      elsif item.is_a?(Array)
                        item.map { |entry| entry.is_a?(Hash) ? replace_status(entry, provider_value) : entry }
                      else
                        item
                      end
      end
    end

    def host_operation_from_provider(provider_body)
      operation = {}
      Array(@blueprint["field_mappings"]).select { |mapping| mapping["direction"].to_s == "request" }.each do |mapping|
        provider_path = mapping.fetch("provider_path").sub("request.", "")
        value = read_path(provider_body, provider_path)
        next if value.nil?

        value = provider_to_host_amount(value) if mapping["canonical_path"] == "operation.amount"
        set_path(operation, mapping.fetch("canonical_path").sub("operation.", ""), value)
      end
      operation
    end

    def provider_to_host_amount(value)
      conversion = @blueprint.dig("money", "response_conversion") || {}
      factor = conversion["factor_decimal"] || conversion["factor"] || 1
      amount = BigDecimal(value.to_s) * BigDecimal(factor.to_s)
      amount.frac.zero? ? amount.to_i : amount.to_f
    end

    def schema_example(schema)
      return nil unless schema.is_a?(Hash)
      return schema["example"] if schema.key?("example")
      return schema["examples"].first if schema["examples"].is_a?(Array) && !schema["examples"].empty?
      return schema["default"] if schema.key?("default")
      return schema["enum"].first if schema["enum"].is_a?(Array) && !schema["enum"].empty?

      type = schema["type"].to_s
      case type
      when "object"
        schema.fetch("properties", {}).each_with_object({}) do |(name, property), result|
          value = schema_example(property)
          result[name] = value unless value.nil?
        end
      when "array"
        [schema_example(schema["items"])]
      when "integer"
        schema.fetch("minimum", 1)
      when "number"
        schema.fetch("minimum", 1)
      when "boolean"
        false
      when "string"
        return "12.50" if schema["pattern"].to_s.match?(/\d.*\./) || schema["description"].to_s.match?(/amount|money|major|minor|currency|сумм|денег/i)

        case schema["format"]
        when "uuid" then "00000000-0000-4000-8000-000000000001"
        when "date-time" then "2026-01-01T00:00:00Z"
        when "email" then "preview@example.test"
        else "preview-value"
        end
      end
    end

    def merge_missing(primary, fallback)
      return primary unless fallback.is_a?(Hash)

      fallback.each_with_object(Util.deep_dup(primary)) do |(key, value), result|
        if result[key].is_a?(Hash) && value.is_a?(Hash)
          result[key] = merge_missing(result[key], value)
        else
          result[key] = Util.deep_dup(value) unless result.key?(key)
        end
      end
    end

    def read_path(object, path)
      path.to_s.split(".").reduce(object) { |current, key| current.is_a?(Hash) ? (current[key] || current[key.to_sym]) : nil }
    end

    def set_path(object, path, value)
      keys = path.to_s.split(".")
      leaf = keys.pop
      target = keys.reduce(object) { |current, key| current[key] ||= {} }
      target[leaf] = value
    end
  end

  class DeterministicGenerator
    def generate(blueprint, manifest, output_dir, examples: {}, spec_document: nil, readiness: nil)
      FileUtils.mkdir_p(output_dir)
      fixture_data = fixtures(blueprint, examples, spec_document: spec_document)
      files = {
        "provider_blueprint.json" => Util.pretty_json(blueprint) + "\n",
        "review_manifest.json" => Util.pretty_json(manifest.to_h) + "\n",
        "service.rb" => RubyProjection.new(blueprint).render,
        "fixtures.json" => Util.pretty_json(fixture_data) + "\n",
        "INTEGRATION.md" => integration_doc(blueprint),
        "contract_smoke.rb" => smoke_harness(blueprint, fixture_data)
      }
      files.each { |name, content| File.write(File.join(output_dir, name), content, mode: "w", encoding: "UTF-8") }
      readiness_files = readiness ? IntegrationReadiness.write(output_dir, readiness) : []
      files.keys.map { |name| File.join(output_dir, name) } + readiness_files
    end

    private

    def fixtures(blueprint, examples, spec_document: nil)
      result = FixtureSynthesizer.new(blueprint, spec_document: spec_document, fallback_examples: examples).build
      result["extra_operations"] = blueprint.fetch("extra_operations")
      result["blueprint_expectations"] = {
        "source_fingerprint" => blueprint.dig("source", "spec_fingerprint"),
        "sandbox_url" => blueprint.fetch("servers").find { |server| server["environment"] == "sandbox" }&.fetch("url"),
        "canonical_operations" => blueprint.fetch("operations").map { |item| item["canonical"] },
        "money_request_factor" => blueprint.dig("money", "request_conversion", "factor"),
        "money_response_factor" => blueprint.dig("money", "response_conversion", "factor"),
        "status_map" => blueprint.fetch("statuses").to_h { |item| [item.fetch("provider_value"), item.fetch("canonical_value")] },
        "webhook_events" => blueprint.dig("webhook", "events")
      }
      result
    end

    def integration_doc(blueprint)
      endpoint_lines = blueprint.fetch("endpoints").map { |endpoint| "- `#{endpoint["method"]} #{endpoint["path"]}` - #{endpoint["operation_id"]}#{endpoint["canonical"] ? " -> #{endpoint["canonical"]}" : " - EXTRA_OPERATION"}" }.join("\n")
      status_lines = blueprint.fetch("statuses").map { |item| "| `#{item["provider_value"]}` | `#{item["canonical_value"]}` |" }.join("\n")
      status_lines = "| — | mapping unresolved |" if status_lines.empty?
      server_lines = blueprint.fetch("servers").map { |server| "- #{server["environment"]}: `#{server["url"]}`" }.join("\n")
      auth = blueprint.fetch("auth", {})
      auth_strategy = auth.fetch("strategy", {})
      auth_name = auth_strategy["name"] || "not resolved"
      auth_transport = auth_strategy["transport"] || "not resolved"
      provider_slug = Util.slug(blueprint.dig("provider", "name"))
      provider_class = "Provider::#{Util.camel(blueprint.dig("provider", "name"))}Service"
      idempotency = blueprint.fetch("idempotency", {})
      idempotency_policy = idempotency.dig("adapter_policy", "send_header") || "not resolved"
      error_lines = blueprint.fetch("errors").select { |item| item["http_status"].to_i >= 400 }.map do |item|
        codes = Array(item["provider_codes"]).map { |code| "#{code["code"]} → #{code["category"]}" }.uniq
        label = codes.empty? ? item["canonical_category"] : codes.join(", ")
        "- HTTP #{item["http_status"]}: #{label}#{item["retry_after_header"] ? " (сохранять #{item["retry_after_header"]})" : ""}"
      end.uniq.join("\n")
      <<~DOC
        # Интеграция #{blueprint.dig("provider", "name")}

        Сгенерировано из Provider Blueprint v#{blueprint.fetch("schema_version")}.

        - Sandbox URL: #{blueprint.fetch("servers").find { |server| server["environment"] == "sandbox" }&.fetch("url", "unknown")}
        - Базовый URL runtime: `#{Util.slug(blueprint.dig("provider", "name")).upcase}_BASE_URL` (по умолчанию используется sandbox URL)
        - Аутентификация: #{blueprint.dig("auth", "selected") || "unknown"}
        - Сумма: #{blueprint.dig("money", "host", "representation")} #{blueprint.dig("money", "host", "currency")} -> #{blueprint.dig("money", "provider", "unit_name")}; scale #{blueprint.dig("money", "provider", "scale")}; request factor #{blueprint.dig("money", "request_conversion", "factor")}
        - Обязательность Idempotency по спецификации: #{blueprint.dig("idempotency", "spec_required")}
        - Подпись webhook: #{blueprint.dig("webhook", "signature", "algorithm")} / #{blueprint.dig("webhook", "signature", "encoding")}
        - Действия callback: #{format_mapping(blueprint.dig("base_service_profile", "callback_actions"))}
        - Дополнительные operations: #{blueprint.fetch("extra_operations").map { |item| item["path"] }.join(", ")}

        ## Endpoint-ы

        #{endpoint_lines}

        ## Маппинг статусов

        | Статус провайдера | Space Payments |
        |---|---|
        #{status_lines}

        Источник: resolved Provider Blueprint `statuses`.

        ## ProviderGateway / конфигурация

        - Service class: `#{provider_class}`; BaseService: `#{blueprint.dig("base_service_profile", "class_name") || "not resolved"}`
        - Окружения и base URL:
        #{server_lines}
        - Auth strategy: `#{auth.fetch("selected", "not resolved")}` (`#{auth_strategy["kind"] || "not resolved"}` / `#{auth_transport}` / `#{auth_name}`)
        - API key/config parameter: `#{auth_name}`; runtime URL override: `#{provider_slug.upcase}_BASE_URL`
        - Webhook secret: передаётся в generated adapter, если Blueprint содержит signature semantics (`#{blueprint.dig("webhook", "signature", "header") || "not resolved"}`)
        - Idempotency по спецификации: `#{idempotency["spec_required"]}`; adapter policy: `#{idempotency_policy}`; header: `#{idempotency["header"] || "not resolved"}`
        - Supported canonical operations: `#{Array(blueprint.dig("base_service_profile", "canonical_operations")).join("`, `")}`

        Параметры, которые необходимо передать в окружение/host gateway, должны
        быть адаптированы к API host-приложения; этот generated документ не
        объявляет production framework contract, которого нет в Blueprint.

        ## Проверка request и ошибки

        Сгенерированный адаптер проверяет обязательные поля, enums, patterns, lengths,
        conditional recipient fields и host-side minimum amount до отправки.
        HTTP-ошибки возвращаются без blind retries; POST retries после rate limit
        должны повторно использовать тот же idempotency key. Если host не передал
        `operation.idempotency_key`, fallback key хранится только в памяти процесса;
        durability across process restart не гарантируется.

        #{error_lines}

        Обработка webhook использует fail-closed поведение, если raw body,
        signature, secret или known event outcome отсутствуют либо некорректны.

        Сгенерированный Ruby является проекцией resolved Blueprint. Перед production
        use проверьте решения review и контракт host BaseService.
      DOC
    end

    def format_mapping(value)
      return "не разрешены; terminal events завершаются безопасным отказом" unless value.is_a?(Hash)

      "{" + value.map { |key, item| "#{key.inspect} => #{item.inspect}" }.join(", ") + "}"
    end

    def smoke_harness(blueprint, examples)
      provider_class = "Provider::#{Util.camel(blueprint.dig("provider", "name"))}Service"
      operation = examples.dig("create_request", "operation") || examples.dig("request", "operation") || {}
      operation = { "amount" => 1, "currency" => blueprint.dig("money", "host", "currency"), "external_id" => "smoke-operation", "recipient" => { "type" => "sbp", "phone" => "70000000000", "bank_code" => "000000000" } }.merge(operation)
      event, expected_status = blueprint.dig("webhook", "events")&.first
      event ||= "completed"
      expected_status ||= "approved"
      provider_status = event.to_s.split(".").last
      identifier_field = blueprint.dig("webhook", "identifier_field") || "id"
      request_conversion = blueprint.dig("money", "request_conversion") || {}
      provider_amount_path = blueprint.dig("money", "provider", "field").to_s.sub("request.", "").split(".")
      expected_provider_amount = if request_conversion["direction"] == "same_unit"
                                  operation.fetch("amount")
                                else
                                  (BigDecimal(operation.fetch("amount").to_s) * BigDecimal((request_conversion["factor_decimal"] || request_conversion["factor"]).to_s)).to_i
                                end
      <<~RUBY
        # frozen_string_literal: true

        require "json"
        require "openssl"

        module Provider
          class BaseService
            def check_conditions(_operation, _request_method); success; end
            def success(value = true); { "ok" => true, "value" => value }; end
            def failure(status = nil, code = nil, message = nil); code.nil? && message.nil? ? { "ok" => false, "error" => status } : { "ok" => false, "http_status" => status, "error" => message || code, "error_code" => code, "message" => message }; end
            def approve_operation(operation); { "ok" => true, "action" => "approve_operation", "operation" => operation }; end
            def reject_operation(operation); { "ok" => true, "action" => "reject_operation", "operation" => operation }; end
          end
        end

        require_relative "service"

        service = #{provider_class}.new(api_key: "smoke-key", webhook_secret: "smoke-secret")
        operation = #{ruby_literal(operation)}
        request = service.build_create_request(operation)
        provider_amount = request.dig("body", *#{ruby_literal(provider_amount_path)})
        raise "amount conversion smoke check failed" unless provider_amount == #{ruby_literal(expected_provider_amount)} || provider_amount.to_s == #{ruby_literal(expected_provider_amount.to_s)}
        raise "sandbox URL smoke check failed" unless request.fetch("url").start_with?(#{blueprint.fetch("servers").find { |server| server["environment"] == "sandbox" }.fetch("url").inspect})

        if #{(blueprint.dig("webhook", "mode") == "polling_only").inspect}
          raise "polling-only callback guard failed" unless service.process_callback(raw_body: "{}", signature: "unused").fetch("ok") == false
        else
          body = JSON.generate(#{ruby_literal(identifier_field => "smoke-provider-id", "event" => event, "status" => provider_status, "external_id" => operation.fetch("external_id"))})
          signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "smoke-secret", body)
          callback = service.process_callback(raw_body: body, signature: signature)
          raise "webhook smoke check failed" unless callback.fetch("status") == #{expected_status.inspect}
          raise "webhook fail-closed check failed" unless service.process_callback(raw_body: body, signature: "bad").fetch("ok") == false
        end
        puts "contract smoke passed"
      RUBY
    end

    def ruby_literal(value)
      case value
      when Hash
        "{#{value.keys.sort_by(&:to_s).map { |key| "#{key.inspect} => #{ruby_literal(value[key])}" }.join(", ")}}"
      when Array
        "[#{value.map { |item| ruby_literal(item) }.join(", ")}]"
      when String
        value.inspect
      when true, false, nil, Numeric
        value.inspect
      else
        value.to_s.inspect
      end
    end
  end

  class Verification
    def ruby_syntax(path)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-c", path)
      { "path" => path, "passed" => status.success?, "stdout" => stdout, "stderr" => stderr }
    end

    def verify(output_dir)
      paths = [File.join(output_dir, "service.rb"), File.join(output_dir, "contract_smoke.rb")]
      syntax = paths.map { |path| ruby_syntax(path) }
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "contract_smoke.rb", chdir: output_dir)
      { "passed" => syntax.all? { |item| item["passed"] } && status.success?, "syntax" => syntax, "smoke" => { "passed" => status.success?, "stdout" => stdout, "stderr" => stderr } }
    end
  end

end
