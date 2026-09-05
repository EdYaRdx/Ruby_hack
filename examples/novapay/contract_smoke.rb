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

service = Provider::NovapayService.new(api_key: "smoke-key", webhook_secret: "smoke-secret")
operation = {"amount" => 15000, "currency" => "RUB", "external_id" => "op_abc123", "idempotency_key" => "key-1", "recipient" => {"bank_code" => "044525225", "bank_name" => "Сбербанк", "phone" => "79001234567", "type" => "sbp"}}
request = service.build_create_request(operation)
provider_amount = request.dig("body", *["amount"])
raise "amount conversion smoke check failed" unless provider_amount == 1500000 || provider_amount.to_s == "1500000"
raise "sandbox URL smoke check failed" unless request.fetch("url").start_with?("https://api.sandbox.novapay.example/v1")

if false
  raise "polling-only callback guard failed" unless service.process_callback(raw_body: "{}", signature: "unused").fetch("ok") == false
else
  body = JSON.generate({"event" => "payout.completed", "external_id" => "op_abc123", "payout_id" => "smoke-provider-id", "status" => "completed"})
  signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "smoke-secret", body)
  callback = service.process_callback(raw_body: body, signature: signature)
  raise "webhook smoke check failed" unless callback.fetch("status") == "approved"
  raise "webhook fail-closed check failed" unless service.process_callback(raw_body: body, signature: "bad").fetch("ok") == false
end
puts "contract smoke passed"
