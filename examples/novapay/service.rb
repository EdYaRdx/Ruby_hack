# frozen_string_literal: true

require "bigdecimal"
require "json"
require "openssl"
require "securerandom"

module Provider
  class NovapayService < BaseService
    PROVIDER_NAME = "NovaPay".freeze
    BASE_URL = ENV.fetch("NOVAPAY_BASE_URL", "https://api.sandbox.novapay.example/v1").sub(%r{/$}, "").freeze
    AUTH_STRATEGY = {"kind" => "api_key", "name" => "X-API-Key", "transport" => "header"}.freeze
    CREATE_METHOD = "POST".freeze
    STATUS_METHOD = "GET".freeze
    STATUS_PARAMETER = "payout_id".freeze
    WEBHOOK_ID_FIELD = "payout_id".freeze
    CALLBACK_ACTIONS = {"approved" => "approve_operation", "in_progress" => nil, "rejected" => "reject_operation"}.freeze
    ENDPOINTS = {"cancelPayout" => {"canonical" => nil, "method" => "POST", "path" => "/payouts/{payout_id}/cancel", "success_statuses" => ["200"]}, "createPayout" => {"canonical" => "create_request", "method" => "POST", "path" => "/payouts", "success_statuses" => ["201"]}, "getBalance" => {"canonical" => nil, "method" => "GET", "path" => "/balance", "success_statuses" => ["200"]}, "getPayoutStatus" => {"canonical" => "fetch_status", "method" => "GET", "path" => "/payouts/{payout_id}", "success_statuses" => ["200"]}, "payoutWebhook" => {"canonical" => "process_callback", "method" => "POST", "path" => "/webhooks/payout", "success_statuses" => ["200"]}}.freeze
    FIELD_MAPPINGS = [{"canonical_path" => "operation.amount", "decision" => "ACCEPT", "direction" => "request", "factor" => 100, "provenance" => "SPEC_FACT", "provider_path" => "request.amount", "required" => true, "transform" => "multiply"}, {"canonical_path" => "operation.currency", "decision" => "ACCEPT", "direction" => "request", "factor" => 1, "provenance" => "SPEC_FACT", "provider_path" => "request.currency", "required" => true, "transform" => "identity"}, {"canonical_path" => "operation.external_id", "decision" => "ACCEPT", "direction" => "request", "factor" => 1, "provenance" => "SPEC_FACT", "provider_path" => "request.external_id", "required" => true, "transform" => "identity"}, {"canonical_path" => "operation.recipient", "decision" => "ACCEPT", "direction" => "request", "factor" => 1, "provenance" => "SPEC_FACT", "provider_path" => "request.recipient", "required" => true, "transform" => "identity"}, {"canonical_path" => "operation.provider_operation_id", "decision" => "ACCEPT", "direction" => "response", "factor" => 1, "provenance" => "SPEC_FACT", "provider_path" => "response.id", "required" => false, "transform" => "identity"}, {"canonical_path" => "operation.status", "decision" => "ACCEPT", "direction" => "response", "factor" => 1, "provenance" => "SPEC_FACT", "provider_path" => "response.status", "required" => false, "transform" => "status_map"}, {"canonical_path" => "operation.amount", "decision" => "ACCEPT", "direction" => "response", "factor" => 0.01, "provenance" => "SPEC_FACT", "provider_path" => "response.amount", "required" => false, "transform" => "divide"}].freeze
    STATUS_MAP = {"cancelled" => "rejected", "completed" => "approved", "failed" => "rejected", "pending" => "in_progress", "processing" => "in_progress"}.freeze
    ERROR_MODEL = [{"canonical_category" => "unknown_provider_error", "description" => "Выплата создана", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "201", "operation_id" => "createPayout", "provider_codes" => [], "retry_after_header" => nil, "retryable" => false}, {"canonical_category" => "validation_error", "description" => "Некорректный запрос", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "400", "operation_id" => "createPayout", "provider_codes" => [], "retry_after_header" => nil, "retryable" => false}, {"canonical_category" => "unauthorized", "description" => "Невалидный API-ключ", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "401", "operation_id" => "createPayout", "provider_codes" => [{"action" => "refresh_credentials_or_review", "category" => "unauthorized", "code" => "unauthorized", "known_to_schema" => false, "retryable" => false, "unknown_code_policy" => "preserve_and_review"}], "retry_after_header" => nil, "retryable" => false}, {"canonical_category" => "insufficient_balance", "description" => "Недостаточно средств на балансе провайдера", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "402", "operation_id" => "createPayout", "provider_codes" => [{"action" => "review_provider_balance", "category" => "insufficient_balance", "code" => "insufficient_balance", "known_to_schema" => false, "retryable" => false, "unknown_code_policy" => "preserve_and_review"}], "retry_after_header" => nil, "retryable" => false}, {"canonical_category" => "conflict", "description" => "Дубликат по idempotency key", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "409", "operation_id" => "createPayout", "provider_codes" => [], "retry_after_header" => nil, "retryable" => false}, {"canonical_category" => "validation_error", "description" => "Ошибка валидации", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "422", "operation_id" => "createPayout", "provider_codes" => [{"action" => "correct_request", "category" => "validation_error", "code" => "validation_error", "known_to_schema" => false, "retryable" => false, "unknown_code_policy" => "preserve_and_review"}], "retry_after_header" => nil, "retryable" => false}, {"canonical_category" => "rate_limit_exceeded", "description" => "Превышен лимит запросов", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "429", "operation_id" => "createPayout", "provider_codes" => [{"action" => "retry_after_with_same_idempotency_key", "category" => "rate_limit_exceeded", "code" => "rate_limit_exceeded", "known_to_schema" => false, "retryable" => true, "unknown_code_policy" => "preserve_and_review"}], "retry_after_header" => "Retry-After", "retryable" => true}, {"canonical_category" => "internal_error", "description" => "Внутренняя ошибка провайдера", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "500", "operation_id" => "createPayout", "provider_codes" => [], "retry_after_header" => nil, "retryable" => false}, {"canonical_category" => "unknown_provider_error", "description" => "Статус выплаты", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "200", "operation_id" => "getPayoutStatus", "provider_codes" => [], "retry_after_header" => nil, "retryable" => false}, {"canonical_category" => "unauthorized", "description" => "Невалидный API-ключ", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "401", "operation_id" => "getPayoutStatus", "provider_codes" => [{"action" => "refresh_credentials_or_review", "category" => "unauthorized", "code" => "unauthorized", "known_to_schema" => false, "retryable" => false, "unknown_code_policy" => "preserve_and_review"}], "retry_after_header" => nil, "retryable" => false}, {"canonical_category" => "not_found", "description" => "Выплата не найдена", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "404", "operation_id" => "getPayoutStatus", "provider_codes" => [{"action" => "review_identifier", "category" => "not_found", "code" => "not_found", "known_to_schema" => false, "retryable" => false, "unknown_code_policy" => "preserve_and_review"}], "retry_after_header" => nil, "retryable" => false}, {"canonical_category" => "unknown_provider_error", "description" => "Выплата отменена", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "200", "operation_id" => "cancelPayout", "provider_codes" => [], "retry_after_header" => nil, "retryable" => false}, {"canonical_category" => "conflict", "description" => "Невозможно отменить в текущем статусе", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "409", "operation_id" => "cancelPayout", "provider_codes" => [{"action" => "inspect_existing_operation", "category" => "conflict", "code" => "invalid_status", "known_to_schema" => false, "retryable" => false, "unknown_code_policy" => "preserve_and_review"}], "retry_after_header" => nil, "retryable" => false}, {"canonical_category" => "unknown_provider_error", "description" => "Webhook принят", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "200", "operation_id" => "payoutWebhook", "provider_codes" => [], "retry_after_header" => nil, "retryable" => false}, {"canonical_category" => "unknown_provider_error", "description" => "Текущий баланс", "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"], "http_status" => "200", "operation_id" => "getBalance", "provider_codes" => [], "retry_after_header" => nil, "retryable" => false}].freeze
    EXTRA_OPERATIONS = {"cancelPayout" => {"method" => "POST", "path" => "/payouts/{payout_id}/cancel"}, "getBalance" => {"method" => "GET", "path" => "/balance"}}.freeze
    MONEY = {"decision" => "ACCEPT", "host" => {"currency" => "RUB", "evidence" => [{"excerpt" => "operation.amount is major RUB", "locations" => ["profile#/canonical_amount"], "note" => nil, "source" => "BASE_SERVICE_PROFILE"}], "evidence_source" => "BASE_SERVICE_PROFILE", "field" => "operation.amount", "representation" => "major", "source" => "BASE_SERVICE_PROFILE", "unit" => "major"}, "provider" => {"currency" => "RUB", "evidence" => [{"excerpt" => "Сумма в копейках", "locations" => ["#/paths/~1payouts/post/requestBody/content/application~1json/schema/properties/amount/description"], "note" => nil, "source" => "SPEC_DESCRIPTION"}, {"excerpt" => "provider amount unit and subunit", "locations" => ["organizer_case_qa.money"], "note" => nil, "source" => "CASE_DEFAULT"}], "evidence_sources" => ["SPEC_DESCRIPTION", "CASE_DEFAULT"], "field" => "request.amount", "field_candidates" => ["amount"], "nested_money_candidate" => false, "representation" => "minor", "response_field" => "response.amount", "scale" => 100, "scale_source" => "CASE_DEFAULT", "source" => ["SPEC_DESCRIPTION", "CASE_DEFAULT"], "subunit" => "kopecks", "unit" => "minor", "unit_name" => "kopecks"}, "request_conversion" => {"direction" => "major_to_minor", "factor" => 100, "factor_decimal" => "100", "operation" => "multiply", "scale" => 100, "status" => "resolved"}, "response_conversion" => {"direction" => "minor_to_major", "factor" => 0.01, "factor_decimal" => "0.01", "operation" => "divide", "scale" => 100, "status" => "resolved"}}.freeze
    CONSTRAINTS = [{"host_minimum" => 1000, "minimum" => 100000, "path" => "request.amount", "provenance" => "SPEC_FACT", "required" => true, "type" => "integer"}, {"enum" => ["RUB"], "path" => "request.currency", "provenance" => "SPEC_FACT", "required" => true, "type" => "string"}, {"maxLength" => 64, "path" => "request.external_id", "provenance" => "SPEC_FACT", "required" => true, "type" => "string"}, {"path" => "request.recipient", "provenance" => "SPEC_FACT", "required" => true, "type" => "object"}, {"enum" => ["sbp", "card"], "path" => "request.recipient.type", "provenance" => "SPEC_FACT", "required" => true, "type" => "string"}, {"path" => "request.recipient.phone", "pattern" => "^7\\d{10}$", "provenance" => "SPEC_FACT", "required" => true, "type" => "string"}, {"path" => "request.recipient.bank_code", "provenance" => "SPEC_FACT", "required" => false, "type" => "string"}, {"path" => "request.recipient.bank_name", "provenance" => "SPEC_FACT", "required" => false, "type" => "string"}, {"path" => "request.recipient.card_number", "provenance" => "SPEC_FACT", "required" => false, "type" => "string"}].freeze
    WEBHOOK = {"decision" => "ACCEPT", "endpoint" => "POST /webhooks/payout", "events" => {"payout.cancelled" => "rejected", "payout.completed" => "approved", "payout.failed" => "rejected", "payout.processing" => "in_progress"}, "identifier_field" => "payout_id", "raw_body_required" => true, "signature" => {"algorithm" => "HMAC-SHA256", "encoding" => "hex", "header" => "X-NovaPay-Signature", "input" => "raw_body", "required" => true}}.freeze
    IDEMPOTENCY = {"adapter_policy" => {"provenance" => "ADAPTER_POLICY", "send_header" => "if_available"}, "header" => "Idempotency-Key", "retry_policy" => {"name" => "preserve_same_key", "provenance" => "ADAPTER_POLICY"}, "spec_evidence_source" => "SPEC_FACT", "spec_required" => false}.freeze
    CONDITIONALS = [{"required" => ["bank_code"], "type" => "sbp"}, {"required" => ["card_number"], "type" => "card"}].freeze
    CREATE_SUCCESS_STATUSES = ["201"].freeze
    STATUS_SUCCESS_STATUSES = ["200"].freeze
    CALL_SUPER_CONDITIONS = true
    VALIDATION_FAILURE_STATUS = 422
    VALIDATION_FAILURE_CODE = "validation_error"

    def initialize(api_key:, webhook_secret: nil, client: nil)
      @api_key = api_key
      @webhook_secret = webhook_secret
      @client = client
      @idempotency_keys = {}
    end

    def check_conditions(operation, request_method)
      return success if request_method.to_s != "create"

      if CALL_SUPER_CONDITIONS
        base_result = super(operation, request_method)
        return base_result if base_result.is_a?(Hash) && base_result["ok"] == false
      end

      errors = validate_constraints(operation)
      errors.concat(validate_conditionals(operation))
      errors.empty? ? success : failure(VALIDATION_FAILURE_STATUS, VALIDATION_FAILURE_CODE, errors.join("; "))
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
      path = "/payouts"
      { "method" => CREATE_METHOD, "path" => path, "url" => "#{BASE_URL}#{path}", "headers" => headers, "query" => query, "body" => body }
    end

    def create_request(operation, request_method = "create")
      request = build_create_request(operation, request_method)
      return request unless @client

      handle_response(dispatch(request), expected_success: CREATE_SUCCESS_STATUSES)
    end

    def fetch_status(operation)
      id = read(operation, :provider_operation_id) || read(operation, :id)
      return failure("provider operation id is required") if blank?(id)
      path = "/payouts/{payout_id}".sub("{#{STATUS_PARAMETER}}", id.to_s)
      headers, query = authentication
      request = { "method" => STATUS_METHOD, "path" => path, "url" => "#{BASE_URL}#{path}", "headers" => headers, "query" => query }
      return request unless @client

      handle_response(dispatch(request), expected_success: STATUS_SUCCESS_STATUSES)
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
      body = if body_present
               read(response, :body)
             elsif http_status && response.is_a?(Hash) && (response.keys.map(&:to_s) - %w[http_status status_code status headers]).empty?
               nil
             else
               response
             end
      if http_status && !expected_success.map(&:to_s).include?(http_status.to_s)
        return provider_error(response, body, http_status)
      end

      return { "ok" => true, "http_status" => http_status.to_s, "response" => nil } if body.nil? && http_status
      return failure("provider response body is not an object") unless body.is_a?(Hash)
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
      entry = Array(status_entry && status_entry["provider_codes"]).find { |item| provider_code.nil? || item["code"].to_s == provider_code.to_s }
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
