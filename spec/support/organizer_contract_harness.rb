# frozen_string_literal: true

# Test-only approximation of the organizer-provided BaseService contract. It is
# deliberately kept outside lib/ so production code never depends on this
# harness.
module OrganizerContractHarness
  module_function

  def with_base_service
    provider = Provider
    original = provider.const_get(:BaseService)
    provider.send(:remove_const, :BaseService)
    provider.const_set(:BaseService, Class.new do
      attr_reader :base_check_calls, :failure_calls

      def initialize
        @base_check_calls = 0
        @failure_calls = []
      end

      def check_conditions(operation, _request_method)
        @base_check_calls = @base_check_calls.to_i + 1
        return failure(:unprocessable_entity, "base_blocked", "BaseService rejected operation") if operation["base_blocked"]

        success
      end

      def success(value = true)
        { "ok" => true, "value" => value }
      end

      def failure(status = nil, code = nil, message = nil)
        @failure_calls ||= []
        @failure_calls << [status, code, message]
        { "ok" => false, "http_status" => status, "error" => message || code, "error_code" => code, "message" => message }
      end

      def approve_operation(operation)
        { "ok" => true, "action" => "approve_operation", "operation" => operation }
      end

      def reject_operation(operation)
        { "ok" => true, "action" => "reject_operation", "operation" => operation }
      end
    end)
    yield
  ensure
    provider.send(:remove_const, :BaseService) if provider.const_defined?(:BaseService, false)
    provider.const_set(:BaseService, original) if original
  end
end
