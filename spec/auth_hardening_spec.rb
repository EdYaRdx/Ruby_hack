# frozen_string_literal: true

require "yaml"

RSpec.describe "operation-level authentication hardening" do
  def load_spec
    YAML.safe_load(File.read(SpecSupport::SPEC_PATH, encoding: "UTF-8"), aliases: true)
  end

  def write_pipeline(directory, spec)
    spec_path = File.join(directory, "auth-variant.yml")
    File.write(spec_path, YAML.dump(spec), encoding: "UTF-8")
    ProviderCompiler::Pipeline.new(
      spec_path: spec_path,
      profile_path: SpecSupport::PROFILE_PATH,
      defaults_path: SpecSupport::DEFAULTS_PATH
    )
  end

  it "accepts identical API-key auth on create and status" do
    pipeline = SpecSupport.pipeline
    auth = pipeline.blueprint.fetch("auth")

    expect(pipeline.blueprint.fetch("decision")).to eq("ACCEPT")
    expect(auth.fetch("operation_requirements")).to include(
      include("canonical" => "create_request", "strategy" => include("kind" => "api_key")),
      include("canonical" => "fetch_status", "strategy" => include("kind" => "api_key"))
    )
  end

  it "blocks mixed API-key create and Bearer status auth" do
    Dir.mktmpdir("auth-mixed") do |directory|
      spec = load_spec
      spec["components"]["securitySchemes"]["BearerAuth"] = {
        "type" => "http",
        "scheme" => "bearer"
      }
      spec["paths"]["/payouts/{payout_id}"]["get"]["security"] = [{ "BearerAuth" => [] }]
      pipeline = write_pipeline(directory, spec)
      auth = pipeline.blueprint.fetch("auth")

      expect(auth.fetch("operation_requirements")).to include(
        include("canonical" => "create_request", "strategy" => include("kind" => "api_key")),
        include("canonical" => "fetch_status", "strategy" => include("kind" => "bearer"))
      )
      expect(pipeline.blueprint.fetch("decision")).to eq("REVIEW_REQUIRED")
      expect(pipeline.manifest.to_h.fetch("decisions")).to include(
        include("decision_id" => "auth:security-schemes", "outcome" => "REVIEW_REQUIRED", "severity" => "BLOCKING")
      )

      files = ProviderCompiler::DeterministicGenerator.new.generate(pipeline.blueprint, pipeline.manifest, File.join(directory, "review"))
      expect(files.map { |path| File.basename(path) }).to contain_exactly("provider_blueprint.json", "review_manifest.json", "INTEGRATION.md")
      expect(File).not_to exist(File.join(directory, "review", "service.rb"))
    end
  end

  it "does not treat an explicitly public webhook as mixed outbound auth" do
    pipeline = SpecSupport.pipeline
    auth = pipeline.blueprint.fetch("auth")

    expect(pipeline.blueprint.fetch("decision")).to eq("ACCEPT")
    expect(auth.fetch("operation_requirements").map { |item| item.fetch("canonical") }).to contain_exactly("create_request", "fetch_status")
    expect(pipeline.blueprint.dig("webhook", "signature", "header")).to eq("X-NovaPay-Signature")
  end

  it "accepts root-level auth inherited by create with explicit identical status auth" do
    Dir.mktmpdir("auth-root-inheritance") do |directory|
      spec = load_spec
      spec["security"] = [{ "ApiKeyAuth" => [] }]
      spec["paths"]["/payouts"]["post"].delete("security")
      pipeline = write_pipeline(directory, spec)
      requirements = pipeline.blueprint.dig("auth", "operation_requirements")

      expect(pipeline.blueprint.fetch("decision")).to eq("ACCEPT")
      expect(requirements).to include(
        include("canonical" => "create_request", "security_source" => "root", "strategy" => include("kind" => "api_key")),
        include("canonical" => "fetch_status", "security_source" => "operation", "strategy" => include("kind" => "api_key"))
      )
    end
  end
end
