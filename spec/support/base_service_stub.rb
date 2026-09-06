# frozen_string_literal: true

module Provider
  class BaseService
    def check_conditions(_operation, _request_method)
      success
    end

    def success(result: nil)
      { "ok" => true, "result" => result }
    end

    def failure(code, i18n_key)
      { "ok" => false, "failure_code" => code, "i18n_key" => i18n_key }
    end

    def approve_operation(operation)
      { "status" => "approved", "operation" => operation }
    end

    def reject_operation(operation)
      { "status" => "rejected", "operation" => operation }
    end
  end
end
