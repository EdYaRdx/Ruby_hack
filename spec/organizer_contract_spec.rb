# frozen_string_literal: true

require "yaml"

RSpec.describe "organizer contract alignment" do
  let(:pipeline) { SpecSupport.pipeline }

  def host_operation(overrides = {})
    {
      "amount" => "1500.50",
      "currency" => "RUB",
      "id" => "op-organizer-1",
      "payout_requisite" => {
        "sbp" => {
          "phone" => "79001234567",
          "bank_code" => "044525225"
        }
      }
    }.merge(overrides)
  end

  def generated_service(directory, client: nil, webhook_secret: nil, source_pipeline: pipeline)
    source_pipeline.validate_blueprint!
    ProviderCompiler::DeterministicGenerator.new.generate(
      source_pipeline.blueprint,
      source_pipeline.manifest,
      directory,
      examples: source_pipeline.defaults.examples,
      spec_document: source_pipeline.source_document.resolved
    )
    name = "#{ProviderCompiler::Util.camel(source_pipeline.blueprint.dig("provider", "name"))}Service"
    Provider.send(:remove_const, name) if Provider.const_defined?(name, false)
    load File.join(directory, "service.rb")
    Provider.const_get(name).new(api_key: "organizer-key", webhook_secret: webhook_secret, client: client)
  end

  def response_client(response)
    Class.new do
      define_method(:initialize) { |value| @response = value }
      define_method(:request) { |_method, _url, _headers, _body, _query| @response }
    end.new(response)
  end

  it "projects the guaranteed host id into the provider external_id" do
    Dir.mktmpdir("organizer-host-id") do |directory|
      request = generated_service(directory).build_create_request(host_operation)
      expect(request.dig("body", "external_id")).to eq("op-organizer-1")
      expect(request.dig("body", "recipient")).to include("type" => "sbp", "phone" => "79001234567", "bank_code" => "044525225")
    end
  end

  it "converts canonical major RUB to provider kopecks by multiplying by 100" do
    Dir.mktmpdir("organizer-money") do |directory|
      service = generated_service(directory)
      expect(service.build_create_request(host_operation).dig("body", "amount")).to eq(150_050)
      expect(service.host_amount_to_provider("12.34")).to eq(1234)
    end
  end

  it "converts provider kopecks back to canonical major RUB" do
    Dir.mktmpdir("organizer-money-inverse") do |directory|
      service = generated_service(directory)
      expect(service.provider_amount_to_host(150_050).to_f).to eq(1500.50)
    end
  end

  it "treats request_method as the logical gateway method while emitting HTTP POST" do
    Dir.mktmpdir("organizer-request-method") do |directory|
      request = generated_service(directory).build_create_request(host_operation)
      expect(request).to include("method" => "POST", "path" => "/payouts")
    end
  end

  it "projects the card branch from payout_requisite without requiring a top-level phone" do
    Dir.mktmpdir("organizer-card") do |directory|
      operation = host_operation(
        "payout_requisite" => { "card_number" => "4111111111111111", "phone" => "79001234567" }
      )
      request = generated_service(directory).build_create_request(operation)
      expect(request.dig("body", "recipient")).to include("type" => "card", "card_number" => "4111111111111111", "phone" => "79001234567")
    end
  end

  it "rejects an explicit request_method that conflicts with the requisite shape" do
    Dir.mktmpdir("organizer-request-conflict") do |directory|
      service = generated_service(directory)
      result = service.check_conditions(host_operation, "card")
      expect(result).to include("ok" => false, "failure_code" => "bad_request", "i18n_key" => "provider.invalid_request")
    end
  end

  it "returns create success through result.id" do
    Dir.mktmpdir("organizer-create-result") do |directory|
      response = { "http_status" => 201, "body" => { "id" => "np-organizer-1", "status" => "pending", "amount" => 150_050 } }
      result = generated_service(directory, client: response_client(response)).create_request(host_operation)
      expect(result).to include("ok" => true, "result" => { "id" => "np-organizer-1" })
      expect(result).not_to have_key("response")
    end
  end

  it "fetches status by the provider id supplied by the platform and approves terminal success" do
    Dir.mktmpdir("organizer-fetch-approved") do |directory|
      response = { "http_status" => 200, "body" => { "id" => "np-organizer-1", "status" => "completed", "amount" => 150_050 } }
      result = generated_service(directory, client: response_client(response)).fetch_status("id" => "np-organizer-1")
      expect(result).to include("status" => "approved", "action" => "approve_operation", "terminal" => true)
    end
  end

  it "does not call a terminal helper for an in-progress status" do
    Dir.mktmpdir("organizer-fetch-progress") do |directory|
      response = { "http_status" => 200, "body" => { "id" => "np-organizer-1", "status" => "processing", "amount" => 150_050 } }
      result = generated_service(directory, client: response_client(response)).fetch_status("id" => "np-organizer-1")
      expect(result).to include("status" => "in_progress", "action" => "none", "terminal" => false)
    end
  end

  it "binds an approved webhook to approve_operation" do
    Dir.mktmpdir("organizer-webhook-approved") do |directory|
      service = generated_service(directory, webhook_secret: "organizer-secret")
      body = JSON.generate("event" => "payout.completed", "status" => "completed", "payout_id" => "np-organizer-1")
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "organizer-secret", body)
      expect(service.process_callback(raw_body: body, signature: signature)).to include("status" => "approved", "action" => "approve_operation", "terminal" => true)
    end
  end

  it "binds a declined webhook to reject_operation" do
    Dir.mktmpdir("organizer-webhook-declined") do |directory|
      service = generated_service(directory, webhook_secret: "organizer-secret")
      body = JSON.generate("event" => "payout.failed", "status" => "failed", "payout_id" => "np-organizer-1")
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "organizer-secret", body)
      expect(service.process_callback(raw_body: body, signature: signature)).to include("status" => "rejected", "action" => "reject_operation", "terminal" => true)
    end
  end

  it "verifies the exact raw callback body while consuming the already parsed payload" do
    Dir.mktmpdir("organizer-webhook-raw") do |directory|
      service = generated_service(directory, webhook_secret: "organizer-secret")
      body = "{\n  \"event\": \"payout.completed\",\n  \"status\": \"completed\",\n  \"payout_id\": \"np-organizer-1\"\n}"
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "organizer-secret", body)
      parsed = JSON.parse(body)
      expect(service.process_callback(raw_body: body, signature: signature, parsed_payload: parsed)).to include("status" => "approved", "ok" => true)
    end
  end

  it "fails closed when raw callback body is missing" do
    Dir.mktmpdir("organizer-webhook-missing-body") do |directory|
      result = generated_service(directory, webhook_secret: "organizer-secret").process_callback(signature: "unused")
      expect(result).to include("ok" => false, "failure_code" => "unprocessable_entity", "error_code" => "missing_raw_body")
    end
  end

  it "fails closed when callback signature is invalid" do
    Dir.mktmpdir("organizer-webhook-invalid-signature") do |directory|
      service = generated_service(directory, webhook_secret: "organizer-secret")
      body = JSON.generate("event" => "payout.completed", "status" => "completed", "payout_id" => "np-organizer-1")
      expect(service.process_callback(raw_body: body, signature: "bad")).to include("ok" => false, "error_code" => "invalid_webhook_signature")
    end
  end

  it "maps amount_limit_exceeded to the platform validation failure contract" do
    Dir.mktmpdir("organizer-error-mapping") do |directory|
      response = { "http_status" => 422, "body" => { "error" => { "code" => "amount_limit_exceeded", "message" => "limit" } } }
      result = generated_service(directory, client: response_client(response)).create_request(host_operation)
      expect(result).to include("ok" => false, "failure_code" => "unprocessable_entity", "i18n_key" => "provider.amount_limit_exceeded", "error_code" => "amount_limit_exceeded")
    end
  end

  it "keeps optional provider idempotency evidence separate from adapter policy" do
    default = pipeline.blueprint.fetch("idempotency")
    always = SpecSupport.pipeline(adapter_policy: "always").blueprint.fetch("idempotency")
    expect(default).to include("spec_required" => false, "spec_evidence_source" => "SPEC_FACT")
    expect(default.dig("adapter_policy", "provenance")).to eq("ADAPTER_POLICY")
    expect(always).to include("spec_required" => false)
    expect(always.dig("adapter_policy", "send_header")).to eq("always")
  end

  it "keeps the official getPayoutStatus operationId as the fetch_status binding" do
    endpoint = pipeline.blueprint.fetch("endpoints").find { |item| item["canonical"] == "fetch_status" }
    expect(endpoint).to include("operation_id" => "getPayoutStatus", "method" => "GET", "path" => "/payouts/{payout_id}")
  end

  it "preserves balance as a non-blocking EXTRA_OPERATION" do
    extra = pipeline.blueprint.fetch("extra_operations").find { |item| item["path"] == "/balance" }
    expect(extra).to include("kind" => "EXTRA_OPERATION", "preserved" => true, "blocking" => false)
    expect(pipeline.blueprint.fetch("operations").map { |item| item["canonical"] }).not_to include("balance")
  end

  it "does not persist a provider id inside the generated service instance" do
    Dir.mktmpdir("organizer-no-persistence") do |directory|
      response = { "http_status" => 201, "body" => { "id" => "np-organizer-1", "status" => "pending", "amount" => 150_050 } }
      service = generated_service(directory, client: response_client(response))
      result = service.create_request(host_operation)
      expect(result.dig("result", "id")).to eq("np-organizer-1")
      expect(service.instance_variables).not_to include(:@provider_operation_id)
    end
  end

  it "preserves an unknown required requisite and blocks unsafe runtime generation" do
    Dir.mktmpdir("organizer-review") do |directory|
      spec = YAML.safe_load(File.read(SpecSupport::SPEC_PATH, encoding: "UTF-8"), aliases: true)
      recipient = spec.dig("components", "schemas", "Recipient")
      recipient["properties"]["iban"] = { "type" => "string" }
      recipient["required"] << "iban"
      spec_path = File.join(directory, "novapay-with-unknown-requisite.yml")
      File.write(spec_path, YAML.dump(spec), encoding: "UTF-8")
      review_pipeline = ProviderCompiler::Pipeline.new(spec_path: spec_path, profile_path: SpecSupport::PROFILE_PATH, defaults_path: SpecSupport::DEFAULTS_PATH)

      expect(review_pipeline.blueprint.fetch("decision")).to eq("REVIEW_REQUIRED")
      expect(review_pipeline.blueprint.dig("host_projection", "requirements")).to include(include("provider_field" => "iban", "mapping" => nil, "generation_impact" => "BLOCKING"))
      expect(review_pipeline.manifest.to_h.fetch("decisions")).to include(include("decision_id" => "host:requisite-mapping", "severity" => "BLOCKING"))

      files = ProviderCompiler::DeterministicGenerator.new.generate(review_pipeline.blueprint, review_pipeline.manifest, File.join(directory, "review"))
      expect(files.map { |path| File.basename(path) }).to contain_exactly("provider_blueprint.json", "review_manifest.json", "INTEGRATION.md")
      expect(File).not_to exist(File.join(directory, "review", "service.rb"))
      integration_doc = File.read(File.join(directory, "review", "INTEGRATION.md"), encoding: "UTF-8")
      expect(integration_doc).to include("iban", "required: `true`", "host source: `operation.payout_requisite`")
    end
  end

  it "exposes the host contract in the resolved Blueprint" do
    expect(pipeline.blueprint.dig("base_service_profile", "host_operation")).to include(
      "id" => "operation.id",
      "amount" => "operation.amount",
      "payout_requisite" => "operation.payout_requisite"
    )
    expect(pipeline.blueprint.dig("base_service_profile", "create_result")).to include("wrapper" => "result", "field" => "id")
  end

  it "uses the resolved status table for terminal and non-terminal provider values" do
    expect(pipeline.blueprint.fetch("statuses")).to include(
      include("provider_value" => "processing", "canonical_value" => "in_progress"),
      include("provider_value" => "completed", "canonical_value" => "approved"),
      include("provider_value" => "failed", "canonical_value" => "rejected")
    )
  end
end
