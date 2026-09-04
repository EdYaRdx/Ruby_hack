# frozen_string_literal: true

RSpec.describe "independent Aurora Transfers provider" do
  let(:spec_path) { File.join(SpecSupport::ROOT, "fixtures", "aurora_transfer_api.yaml") }
  let(:profile_path) { File.join(SpecSupport::ROOT, "profiles", "aurora_payments_v1.yml") }
  let(:empty_defaults) { File.join(SpecSupport::ROOT, "fixtures", "empty_case_defaults.yml") }
  let(:resolved_defaults) { File.join(SpecSupport::ROOT, "fixtures", "aurora_case_defaults.yml") }

  it "maps independent endpoint, auth, nested money and notification evidence generically" do
    pipeline = ProviderCompiler::Pipeline.new(spec_path: spec_path, profile_path: profile_path, defaults_path: empty_defaults)
    blueprint = pipeline.blueprint

    expect(blueprint.fetch("operations").map { |item| item["canonical"] }).to include("create_request", "fetch_status", "process_callback")
    expect(blueprint.dig("auth", "strategy")).to include("kind" => "bearer", "transport" => "header")
    expect(blueprint.dig("money", "provider", "field")).to eq("request.money.value")
    expect(blueprint.dig("money", "provider", "unit")).to eq("major")
    expect(blueprint.dig("money", "decision")).to eq("ACCEPT")
    expect(blueprint.dig("webhook", "endpoint")).to eq("POST /notifications")
    expect(blueprint.dig("webhook", "signature", "header")).to eq("X-Aurora-Signature")
    expect(blueprint.dig("webhook", "decision")).to eq("REVIEW_REQUIRED")
    expect(blueprint.fetch("decision")).to eq("REVIEW_REQUIRED")
  end

  it "resolves provider-specific status/webhook/mapping choices and executes generated Ruby" do
    pipeline = ProviderCompiler::Pipeline.new(spec_path: spec_path, profile_path: profile_path, defaults_path: resolved_defaults)
    blueprint = pipeline.blueprint

    expect(blueprint.dig("money", "decision")).to eq("ACCEPT")
    expect(blueprint.fetch("statuses")).to all(include("decision" => "ACCEPT"))
    expect(blueprint.dig("webhook", "decision")).to eq("ACCEPT")
    expect(blueprint.fetch("field_mappings")).to all(include("decision" => "ACCEPT"))
    expect(blueprint.fetch("extra_operations")).to include(include("path" => "/limits", "kind" => "EXTRA_OPERATION"))

    Dir.mktmpdir("aurora-generated") do |directory|
      ProviderCompiler::BlueprintValidator.new.validate!(blueprint, ProviderCompiler::BaseServiceProfile.load(profile_path))
      ProviderCompiler::DeterministicGenerator.new.generate(blueprint, pipeline.manifest, directory, examples: ProviderCompiler::CaseDefaults.load(resolved_defaults).examples)
      expect(ProviderCompiler::Verification.new.verify(directory).fetch("passed")).to be(true)

      load File.join(directory, "service.rb")
      response_client = Class.new do
        def request(_method, _url, _headers, _body, _query)
          { "http_status" => 200, "body" => { "id" => "tr_123", "status" => "settled", "money" => { "value" => "12.50", "currency" => "USD" } } }
        end
      end.new
      service = Provider::AuroraService.new(api_key: "aurora-key", client: response_client)
      request = service.build_create_request("amount" => "12.50", "currency" => "USD", "external_id" => "op-123", "recipient" => { "type" => "bank", "account" => "US123", "routing_number" => "011000015" })
      expect(request.dig("body", "money", "value")).to eq("12.50")
      expect(request.dig("body", "money", "currency")).to eq("USD")
      status = service.fetch_status("provider_operation_id" => "tr_123")
      expect(status).to include("status" => "approved", "provider_operation_id" => "tr_123")
      expect(status.fetch("amount")).to eq(BigDecimal("12.50"))
    end
  end
end
