# frozen_string_literal: true

module Provider
  class BaseService
    def success(value = true)
      { "ok" => true, "value" => value }
    end

    def failure(message)
      { "ok" => false, "error" => message }
    end

    def approve_operation(operation)
      { "status" => "approved", "operation" => operation }
    end

    def reject_operation(operation)
      { "status" => "rejected", "operation" => operation }
    end
  end
end
