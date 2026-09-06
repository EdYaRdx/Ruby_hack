# frozen_string_literal: true

RSpec.describe "generic OpenAPI status descriptions" do
  it "accepts explicit canonical status mappings without CaseDefaults" do
    pipeline = ProviderCompiler::Pipeline.new(
      spec_path: File.join(SpecSupport::ROOT, "research", "spec_only_success_v1", "specs", "ledger_one.yaml"),
      profile_path: SpecSupport::PROFILE_PATH,
      defaults_path: File.join(SpecSupport::ROOT, "fixtures", "empty_case_defaults.yml")
    )
    statuses = pipeline.blueprint.fetch("statuses").to_h { |item| [item.fetch("provider_value"), item.fetch("canonical_value")] }

    expect(pipeline.blueprint.fetch("decision")).to eq("ACCEPT")
    expect(statuses).to include("queued" => "in_progress", "settled" => "approved", "declined" => "rejected")
    expect(pipeline.blueprint.dig("decisions").find { |item| item["decision_id"] == "status:provider-map" }.fetch("evidence").map { |item| item["source"] }).to include("SPEC_DESCRIPTION")
    expect(pipeline.defaults.data).to be_empty
  end
end
