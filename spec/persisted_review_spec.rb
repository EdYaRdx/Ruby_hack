# frozen_string_literal: true

require "yaml"

RSpec.describe "persisted human Review" do
  def export_override(pipeline, path, resolutions: [["money:amount-units", {
    "money" => {
      "provider_unit" => "minor",
      "provider_subunit" => "kopecks",
      "scale" => 100,
      "source" => "HUMAN_CONFIRMED"
    }
  }]])
    ProviderCompiler::ReviewExporter.write(
      path,
      source_document: pipeline.source_document,
      profile: ProviderCompiler::BaseServiceProfile.load(SpecSupport::PROFILE_PATH),
      provider_name: pipeline.blueprint.dig("provider", "name"),
      resolutions: resolutions
    )
  end

  it "exports only explicit HUMAN_CONFIRMED decisions and reapplies them by fingerprint" do
    pipeline = SpecSupport.pipeline
    Dir.mktmpdir("review-override") do |directory|
      path = File.join(directory, "provider_overrides.yml")
      export_override(pipeline, path)

      document = YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: false)
      expect(document.fetch("schema_version")).to eq(1)
      expect(document.fetch("spec_fingerprint")).to eq(pipeline.source_document.fingerprint)
      expect(document.fetch("decisions").first).to include("provenance" => "HUMAN_CONFIRMED")
      expect(document.to_s).not_to match(/api[_-]?key|secret|password|credential/i)

      reapplied = ProviderCompiler::Pipeline.new(
        spec_path: SpecSupport::SPEC_PATH,
        profile_path: SpecSupport::PROFILE_PATH,
        defaults_path: SpecSupport::DEFAULTS_PATH,
        overrides_path: path
      )
      expect(reapplied.manifest.to_h.dig("review_override", "status")).to eq("APPLIED")
      expect(reapplied.blueprint.dig("money", "provider", "unit")).to eq("minor")
      expect(reapplied.blueprint.dig("money", "request_conversion", "factor")).to eq(100)
    end
  end

  it "rejects changed specs, incompatible profiles, corrupted files and unknown decisions" do
    pipeline = SpecSupport.pipeline
    Dir.mktmpdir("review-override") do |directory|
      path = File.join(directory, "provider_overrides.yml")
      export_override(pipeline, path)

      changed_spec = File.join(directory, "novapay_provider_api.yaml")
      File.write(changed_spec, File.read(SpecSupport::SPEC_PATH, encoding: "UTF-8") + "\n# changed\n", encoding: "UTF-8")
      expect {
        ProviderCompiler::Pipeline.new(spec_path: changed_spec, profile_path: SpecSupport::PROFILE_PATH, defaults_path: SpecSupport::DEFAULTS_PATH, overrides_path: path)
      }.to raise_error(ProviderCompiler::StaleOverrideError, /STALE_OVERRIDE/)

      profile_mismatch = YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: false)
      profile_mismatch["profile_version"] = 99
      mismatch_path = File.join(directory, "profile_mismatch.yml")
      File.write(mismatch_path, YAML.dump(profile_mismatch), encoding: "UTF-8")
      expect {
        ProviderCompiler::Pipeline.new(spec_path: SpecSupport::SPEC_PATH, profile_path: SpecSupport::PROFILE_PATH, defaults_path: SpecSupport::DEFAULTS_PATH, overrides_path: mismatch_path)
      }.to raise_error(ProviderCompiler::ValidationError, /PROFILE_MISMATCH/)

      malformed_path = File.join(directory, "malformed.yml")
      File.write(malformed_path, "decisions: [", encoding: "UTF-8")
      expect { ProviderCompiler::ReviewOverride.load(malformed_path) }.to raise_error(ProviderCompiler::ValidationError, /cannot parse/)

      unknown = YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: false)
      unknown["decisions"][0]["decision_id"] = "unknown:decision"
      unknown_path = File.join(directory, "unknown.yml")
      File.write(unknown_path, YAML.dump(unknown), encoding: "UTF-8")
      expect {
        ProviderCompiler::Pipeline.new(spec_path: SpecSupport::SPEC_PATH, profile_path: SpecSupport::PROFILE_PATH, defaults_path: SpecSupport::DEFAULTS_PATH, overrides_path: unknown_path)
      }.to raise_error(ProviderCompiler::ValidationError, /UNKNOWN_DECISION_ID/)
    end
  end

  it "rejects credential-like data instead of persisting it" do
    expect {
      ProviderCompiler::ReviewOverride.new({
        "schema_version" => 1,
        "provider" => { "name" => "Test" },
        "spec_fingerprint" => "sha256:#{'0' * 64}",
        "root_document_sha256" => "A",
        "base_service_profile" => "space_payments_v1",
        "profile_version" => 1,
        "created_at" => Time.now.utc.iso8601,
        "decisions" => [{ "decision_id" => "x", "value" => { "api_key" => "secret" }, "provenance" => "HUMAN_CONFIRMED" }]
      })
    }.to raise_error(ProviderCompiler::ValidationError, /credential-like data/)
  end
end
