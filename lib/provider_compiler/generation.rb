# frozen_string_literal: true

module ProviderCompiler

  class RubyProjection
    def initialize(blueprint)
      @blueprint = blueprint
    end

    def render
      provider = @blueprint.fetch("provider").fetch("name")
      class_name = "#{Util.camel(provider)}Service"
      endpoints = @blueprint.fetch("endpoints").each_with_object({}) do |endpoint, result|
        result[endpoint.fetch("operation_id").to_s] = { "method" => endpoint.fetch("method"), "path" => endpoint.fetch("path"), "canonical" => endpoint["canonical"] }
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
      base_url_env = "#{Util.slug(provider).upcase}_BASE_URL"
      status_parameter = endpoint_path("fetch_status").to_s[/\{([^}]+)\}/, 1] || "id"
      webhook_id_field = @blueprint.dig("webhook", "identifier_field") || "id"
      erb = ERB.new(TEMPLATE, trim_mode: "-")
      erb.result_with_hash(
        provider: provider,
        class_name: class_name,
        endpoints: ruby_literal(endpoints),
        field_mappings: ruby_literal(@blueprint.fetch("field_mappings")),
        status_map: ruby_literal(status_map),
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
        create_method: endpoint_method("create_request"),
        status_method: endpoint_method("fetch_status"),
        create_path: endpoint_path("create_request"),
        status_path: endpoint_path("fetch_status")
      )
    end

    private

    def endpoint_path(role)
      endpoint = @blueprint.fetch("endpoints").find { |item| item["canonical"] == role }
      endpoint ? endpoint.fetch("path") : (raise Error, "resolved Blueprint has no #{role} endpoint")
    end

    def endpoint_method(role)
      endpoint = @blueprint.fetch("endpoints").find { |item| item["canonical"] == role }
      endpoint ? endpoint.fetch("method") : (raise Error, "resolved Blueprint has no #{role} endpoint")
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
          EXTRA_OPERATIONS = <%= extras %>.freeze
          MONEY = <%= money %>.freeze
          CONSTRAINTS = <%= constraints %>.freeze
          WEBHOOK = <%= webhook %>.freeze
          IDEMPOTENCY = <%= idempotency %>.freeze
          CONDITIONALS = <%= conditions %>.freeze

          def initialize(api_key:, webhook_secret: nil, client: nil)
            @api_key = api_key
            @webhook_secret = webhook_secret
            @client = client
            @idempotency_keys = {}
          end

          def check_conditions(operation, request_method)
            return success if request_method.to_s != "create"

            errors = validate_constraints(operation)
            errors.concat(validate_conditionals(operation))
            errors.empty? ? success : failure(errors.join("; "))
          end

          def build_create_request(operation, request_method = "create")
            raise ArgumentError, "unsupported request_method: #{request_method}" unless request_method.to_s == "create"
            condition_result = check_conditions(operation, request_method)
            raise ArgumentError, condition_result.fetch("error") unless condition_result.fetch("ok")

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

            handle_response(dispatch(request), expected_success: ["201", "200"])
          end

          def fetch_status(operation)
            id = read(operation, :provider_operation_id) || read(operation, :id)
            return failure("provider operation id is required") if blank?(id)
            path = <%= status_path.inspect %>.sub("{#{STATUS_PARAMETER}}", id.to_s)
            headers, query = authentication
            request = { "method" => STATUS_METHOD, "path" => path, "url" => "#{BASE_URL}#{path}", "headers" => headers, "query" => query }
            return request unless @client

            handle_response(dispatch(request), expected_success: ["200"])
          end

          def process_callback(payload)
            return failure("provider has no webhook; polling-only integration") if WEBHOOK["mode"] == "polling_only"

            raw_body = read(payload, :raw_body)
            signature = read(payload, :signature) || read(read(payload, :headers), WEBHOOK.dig("signature", "header"))
            return failure("raw webhook body is required") if blank?(raw_body)
            return failure("webhook signature is required") if blank?(signature)
            return failure("invalid webhook signature") unless verify_webhook_signature(raw_body, signature)

            event = read(payload, :event)
            body = parse_json(raw_body)
            body = body.is_a?(Hash) ? body : {}
            provider_status = (read(payload, :status) || body["status"]).to_s
            event = read(payload, :event) || body["event"]
            canonical = WEBHOOK.fetch("events", {})[event.to_s]
            return failure("unknown webhook event") if canonical.nil? || canonical == "UNKNOWN"

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

          private

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
            return failure("callback action binding is unresolved") if action.nil?
            return failure("callback action is not available on BaseService") unless respond_to?(action)

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

          def dispatch(request)
            if @client.respond_to?(:request)
              @client.request(request.fetch("method"), request.fetch("url"), request.fetch("headers"), request.fetch("body", nil), request.fetch("query", {}))
            elsif request.fetch("method") == "GET" && @client.respond_to?(:get)
              @client.get(request.fetch("url"), request.fetch("headers"))
            elsif request.fetch("method") == "POST" && @client.respond_to?(:post)
              @client.post(request.fetch("url"), request.fetch("headers"), request.fetch("body"))
            else
              raise ArgumentError, "client does not support #{request.fetch("method")}"
            end
          end

          def handle_response(response, expected_success:)
            body_present = response.is_a?(Hash) && (response.key?("body") || response.key?(:body))
            http_status = read(response, :http_status) || read(response, :status_code) || (body_present ? read(response, :status) : nil)
            body = body_present ? read(response, :body) : response
            if http_status && !expected_success.map(&:to_s).include?(http_status.to_s)
              return provider_error(response, body, http_status)
            end

            return failure("provider response body is not an object") unless body.is_a?(Hash)
            mapped = map_provider_response(body)
            provider_status = mapped["provider_status"].to_s
            canonical_status = STATUS_MAP.fetch(provider_status, "unknown")
            result = { "ok" => true, "provider_status" => provider_status, "status" => canonical_status, "response" => body }
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
            { "ok" => false, "http_status" => http_status.to_s, "error" => error, "retry_after" => read(response, :headers).is_a?(Hash) ? read(response, :headers)["Retry-After"] : nil }
          end

          def parse_json(raw_body)
            JSON.parse(raw_body.to_s)
          rescue JSON::ParserError
            nil
          end

          def read(object, key)
            return nil unless object
            object[key] || object[key.to_s] || (object[key.to_sym] if key.respond_to?(:to_sym))
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

  class DeterministicGenerator
    def generate(blueprint, manifest, output_dir, examples: {})
      FileUtils.mkdir_p(output_dir)
      files = {
        "provider_blueprint.json" => JSON.pretty_generate(blueprint) + "\n",
        "review_manifest.json" => JSON.pretty_generate(manifest.to_h) + "\n",
        "service.rb" => RubyProjection.new(blueprint).render,
        "fixtures.json" => JSON.pretty_generate(fixtures(blueprint, examples)) + "\n",
        "INTEGRATION.md" => integration_doc(blueprint),
        "contract_smoke.rb" => smoke_harness(blueprint, examples)
      }
      files.each { |name, content| File.write(File.join(output_dir, name), content, mode: "w", encoding: "UTF-8") }
      files.keys.map { |name| File.join(output_dir, name) }
    end

    private

    def fixtures(blueprint, examples)
      result = Util.deep_dup(examples)
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
      error_lines = blueprint.fetch("errors").select { |item| item["http_status"].to_i >= 400 }.map { |item| "- HTTP #{item["http_status"]}: #{item["provider_codes"].map { |code| code["code"] }.uniq.join(", ")}#{item["retry_after_header"] ? " (соблюдать #{item["retry_after_header"]})" : ""}" }.uniq.join("\n")
      <<~DOC
        # Интеграция #{blueprint.dig("provider", "name")}

        Сгенерировано из Provider Blueprint v#{blueprint.fetch("schema_version")}.

        - Sandbox URL: #{blueprint.fetch("servers").find { |server| server["environment"] == "sandbox" }&.fetch("url", "unknown")}
        - Runtime base URL: `#{Util.slug(blueprint.dig("provider", "name")).upcase}_BASE_URL` (по умолчанию используется sandbox URL)
        - Аутентификация: #{blueprint.dig("auth", "selected") || "unknown"}
        - Сумма: #{blueprint.dig("money", "host", "representation")} #{blueprint.dig("money", "host", "currency")} -> #{blueprint.dig("money", "provider", "unit_name")}; scale #{blueprint.dig("money", "provider", "scale")}; request factor #{blueprint.dig("money", "request_conversion", "factor")}
        - Обязательность Idempotency по spec: #{blueprint.dig("idempotency", "spec_required")}
        - Подпись webhook: #{blueprint.dig("webhook", "signature", "algorithm")} / #{blueprint.dig("webhook", "signature", "encoding")}
        - Действия callback: #{blueprint.dig("base_service_profile", "callback_actions") || "не разрешены; terminal events завершаются безопасным отказом"}
        - Дополнительные operations: #{blueprint.fetch("extra_operations").map { |item| item["path"] }.join(", ")}

        ## Endpoints

        #{endpoint_lines}

        ## Проверка request и ошибки

        Сгенерированный adapter проверяет required fields, enums, patterns, lengths,
        conditional recipient fields и host-side minimum amount до отправки.
        HTTP errors возвращаются без blind retries; POST retries после rate limit
        должны повторно использовать тот же idempotency key.

        #{error_lines}

        Webhook processing использует fail-closed поведение, если raw body,
        signature, secret или known event outcome отсутствуют либо некорректны.

        Сгенерированный Ruby является проекцией resolved Blueprint. Перед production
        use проверьте review decisions и host BaseService contract.
      DOC
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
            def success(value = true); { "ok" => true, "value" => value }; end
            def failure(message); { "ok" => false, "error" => message }; end
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
