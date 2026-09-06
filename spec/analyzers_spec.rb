# frozen_string_literal: true

RSpec.describe "NovaPay analyzers and Blueprint" do
  let(:pipeline) { SpecSupport.pipeline }
  let(:blueprint) { pipeline.blueprint }

  it "maps canonical operations and preserves /balance as a non-blocking extra" do
    operations = pipeline.bundle.sections.fetch(:operations)

    expect(operations.find { |item| item["operation_id"] == "createPayout" }["canonical"]).to eq("create_request")
    expect(operations.find { |item| item["operation_id"] == "getPayoutStatus" }["canonical"]).to eq("fetch_status")
    expect(operations.find { |item| item["operation_id"] == "payoutWebhook" }["canonical"]).to eq("process_callback")
    balance = blueprint.fetch("extra_operations").find { |item| item["operation_id"] == "getBalance" }
    expect(balance).to include("path" => "/balance", "kind" => "EXTRA_OPERATION", "blocking" => false, "preserved" => true)
    expect(blueprint.fetch("operations").map { |item| item["operation_id"] }).not_to include("getBalance")
    expect(blueprint.fetch("servers").first.fetch("url")).to eq("https://api.sandbox.novapay.example/v1")
  end

  it "keeps host and provider money evidence separate and converts major RUB to kopecks" do
    money = blueprint.fetch("money")

    expect(money.dig("host", "unit")).to eq("major")
    expect(money.dig("host", "currency")).to eq("RUB")
    expect(money.dig("host", "evidence_source")).to eq("BASE_SERVICE_PROFILE")
    expect(money.dig("provider", "unit")).to eq("minor")
    expect(money.dig("provider", "subunit")).to eq("kopecks")
    expect(money.dig("provider", "representation")).to eq("minor")
    expect(money.dig("provider", "unit_name")).to eq("kopecks")
    expect(money.dig("provider", "scale")).to eq(100)
    expect(money.dig("provider", "evidence_sources")).to include("SPEC_DESCRIPTION", "CASE_DEFAULT")
    expect(money.dig("request_conversion", "operation")).to eq("multiply")
    expect(money.dig("request_conversion", "factor")).to eq(100)
    expect(money.dig("response_conversion", "operation")).to eq("divide")
    expect(money.dig("host", "evidence").map { |item| item["source"] }).to eq(["BASE_SERVICE_PROFILE"])
    expect(money.dig("provider", "evidence").map { |item| item["source"] }).to include("SPEC_DESCRIPTION", "CASE_DEFAULT")
  end

  it "keeps optional idempotency requiredness distinct from adapter policy" do
    idempotency = blueprint.fetch("idempotency")

    expect(idempotency.fetch("spec_required")).to be(false)
    expect(idempotency.fetch("spec_evidence_source")).to eq("SPEC_FACT")
    expect(idempotency.dig("adapter_policy", "send_header")).to eq("if_available")
    expect(idempotency.dig("adapter_policy", "provenance")).to eq("ADAPTER_POLICY")
  end

  it "maps case-default statuses and represents webhook signature semantics" do
    statuses = blueprint.fetch("statuses").to_h { |item| [item.fetch("provider_value"), item.fetch("canonical_value")] }

    expect(statuses).to eq("pending" => "in_progress", "processing" => "in_progress", "completed" => "approved", "failed" => "rejected", "cancelled" => "rejected")
    expect(blueprint.dig("webhook", "endpoint")).to eq("POST /webhooks/payout")
    expect(blueprint.dig("webhook", "signature")).to include("algorithm" => "HMAC-SHA256", "input" => "raw_body", "encoding" => "hex", "header" => "X-NovaPay-Signature")
    expect(blueprint.dig("webhook", "events")).to include("payout.completed" => "approved", "payout.failed" => "rejected", "payout.processing" => "in_progress", "payout.cancelled" => "rejected")
  end

  it "preserves provider constraints and conservative retry metadata" do
    amount = blueprint.fetch("constraints").find { |item| item["path"] == "request.amount" }
    expect(amount).to include("minimum" => 100000, "host_minimum" => 1000.0)
    rate_limit = blueprint.fetch("errors").find { |item| item["http_status"] == "429" && item["operation_id"] == "createPayout" }
    expect(rate_limit.fetch("retry_after_header")).to eq("Retry-After")
    expect(rate_limit.fetch("provider_codes").find { |item| item["code"] == "rate_limit_exceeded" }).to include("retryable" => true, "action" => "retry_after_with_same_idempotency_key")
  end

  it "passes the Blueprint validator with no blocking decisions for the golden case" do
    expect { pipeline.validate_blueprint! }.not_to raise_error
    expect(blueprint.fetch("decision")).to eq("ACCEPT")
    expect(pipeline.manifest.to_h.dig("summary", "blocking")).to eq(0)
  end

  it "validates money semantics from units instead of accepting a fixed factor" do
    broken = Marshal.load(Marshal.dump(blueprint))
    broken["money"]["request_conversion"]["factor"] = 99
    expect { ProviderCompiler::BlueprintValidator.new.validate!(broken, pipeline.instance_variable_get(:@profile)) }.to raise_error(ProviderCompiler::BlueprintValidationError, /conversion/)
  end

  it "fails closed when critical case defaults are absent" do
    profile = ProviderCompiler::BaseServiceProfile.load(SpecSupport::PROFILE_PATH)
    empty_defaults = ProviderCompiler::CaseDefaults.new
    bundle = ProviderCompiler::AnalyzerEngine.new(profile: profile, defaults: empty_defaults).analyze(pipeline.facts)
    unresolved = ProviderCompiler::BlueprintBuilder.new.build(pipeline.facts, profile, bundle)

    expect(unresolved.fetch("decision")).to eq("REVIEW_REQUIRED")
    expect(unresolved.fetch("decisions").any? { |item| item["severity"] == "BLOCKING" }).to be(true)
    expect(unresolved.fetch("decisions").find { |item| item["decision_id"] == "status:provider-map" }.fetch("outcome")).to eq("REVIEW_REQUIRED")
    expect { ProviderCompiler::BlueprintValidator.new.validate!(unresolved, profile) }.to raise_error(ProviderCompiler::BlueprintValidationError)
  end

  it "reviews contradictory explicit status evidence and preserves both mappings" do
    facts = pipeline.facts
    components = Marshal.load(Marshal.dump(facts.components))
    components["schemas"]["ContradictoryStatusA"] = {
      "type" => "object",
      "properties" => {
        "status" => { "type" => "string", "enum" => ["settled"], "description" => "settled: canonical approved" }
      }
    }
    components["schemas"]["ContradictoryStatusB"] = {
      "type" => "object",
      "properties" => {
        "status" => { "type" => "string", "enum" => ["settled"], "description" => "settled: canonical rejected" }
      }
    }
    contradictory = ProviderCompiler::FactsIR.new(
      source: facts.source,
      operations: facts.operations,
      components: components,
      info: facts.info,
      servers: facts.servers,
      text_facts: facts.text_facts
    )

    result = ProviderCompiler::StatusMapper.new(pipeline.defaults).analyze(contradictory)
    mapping = result.section.find { |item| item["provider_value"] == "settled" }
    decision = result.decisions.first.to_h

    expect(mapping).to include("canonical_value" => "UNKNOWN", "decision" => "REVIEW_REQUIRED")
    expect(mapping.fetch("conflicts").first.fetch("canonical_values")).to contain_exactly("approved", "rejected")
    expect(decision).to include("outcome" => "REVIEW_REQUIRED")
    expect(decision.fetch("conflicts").first.fetch("canonical_values")).to contain_exactly("approved", "rejected")

    profile = ProviderCompiler::BaseServiceProfile.load(SpecSupport::PROFILE_PATH)
    bundle = ProviderCompiler::AnalyzerEngine.new(profile: profile, defaults: pipeline.defaults).analyze(contradictory)
    blueprint = ProviderCompiler::BlueprintBuilder.new.build(contradictory, profile, bundle)
    expect(blueprint.fetch("decision")).to eq("REVIEW_REQUIRED")
    expect { ProviderCompiler::BlueprintValidator.new.validate!(blueprint, profile) }.to raise_error(ProviderCompiler::BlueprintValidationError)
  end

  it "keeps duplicate identical explicit status evidence accepted" do
    facts = pipeline.facts
    components = Marshal.load(Marshal.dump(facts.components))
    ["DuplicateStatusA", "DuplicateStatusB"].each do |name|
      components["schemas"][name] = {
        "type" => "object",
        "properties" => {
          "status" => { "type" => "string", "enum" => ["settled"], "description" => "settled: canonical approved" }
        }
      }
    end
    duplicate = ProviderCompiler::FactsIR.new(
      source: facts.source,
      operations: facts.operations,
      components: components,
      info: facts.info,
      servers: facts.servers,
      text_facts: facts.text_facts
    )

    result = ProviderCompiler::StatusMapper.new(pipeline.defaults).analyze(duplicate)
    mapping = result.section.find { |item| item["provider_value"] == "settled" }

    expect(mapping).to include("canonical_value" => "approved", "decision" => "ACCEPT")
    expect(mapping).not_to have_key("conflicts")
    expect(result.decisions.first.to_h).to include("outcome" => "ACCEPT")
  end
end
