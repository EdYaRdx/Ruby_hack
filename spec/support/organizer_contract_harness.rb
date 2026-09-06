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
        return failure("base_blocked", "provider.base_blocked") if operation["base_blocked"]

        success
      end

      def success(result: nil)
        { "ok" => true, "result" => result }
      end

      def failure(code, i18n_key)
        @failure_calls ||= []
        @failure_calls << [code, i18n_key]
        { "ok" => false, "failure_code" => code.to_s, "i18n_key" => i18n_key }
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
