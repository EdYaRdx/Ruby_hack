# frozen_string_literal: true

module Provider
  class BaseService
    def check_conditions(_operation, _request_method)
      success
    end

    def success(value = true)
      { "ok" => true, "value" => value }
    end

    def failure(status = nil, code = nil, message = nil)
      return { "ok" => false, "error" => status } if code.nil? && message.nil?

      { "ok" => false, "http_status" => status, "error" => message || code, "error_code" => code, "message" => message }
    end

    def approve_operation(operation)
      { "status" => "approved", "operation" => operation }
    end

    def reject_operation(operation)
      { "status" => "rejected", "operation" => operation }
    end
  end
end
