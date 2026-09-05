# frozen_string_literal: true

RSpec.describe "provider_compiler CLI" do
  it "uses matching NovaPay reference defaults when no input paths are supplied" do
    expect(ProviderCompiler::CLI.default_options.fetch(:defaults)).to eq("fixtures/novapay_case_defaults.yml")
  end

  it "uses the repository spec by default and supports an explicit spec override" do
    original = ENV["PROVIDER_SPEC"]
    ENV.delete("PROVIDER_SPEC")
    expect(ProviderCompiler::CLI.default_options.fetch(:spec)).to eq("fixtures/novapay_provider_api.yaml")

    ENV["PROVIDER_SPEC"] = "custom/provider.yml"
    expect(ProviderCompiler::CLI.default_options.fetch(:spec)).to eq("custom/provider.yml")
  ensure
    original.nil? ? ENV.delete("PROVIDER_SPEC") : ENV["PROVIDER_SPEC"] = original
  end

  it "uses empty defaults for an explicit spec unless --defaults is supplied" do
    options = ProviderCompiler::CLI.default_options
    parser = ProviderCompiler::CLI.option_parser(options)
    parser.parse!(["--spec", "fixtures/aurora_transfer_api.yaml"])
    expect(options.fetch(:defaults)).to eq("fixtures/empty_case_defaults.yml")
    expect(options.fetch(:defaults_origin)).to eq("none")

    explicit = ProviderCompiler::CLI.default_options
    ProviderCompiler::CLI.option_parser(explicit).parse!(["--spec", "fixtures/aurora_transfer_api.yaml", "--defaults", "fixtures/aurora_case_defaults.yml"])
    expect(explicit.fetch(:defaults)).to eq("fixtures/aurora_case_defaults.yml")
    expect(explicit.fetch(:defaults_origin)).to eq("fixtures/aurora_case_defaults.yml")
  end

  it "runs analyze/generate and verify through one core pipeline" do
    Dir.mktmpdir("provider-cli") do |directory|
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, SpecSupport::BIN_PATH, "generate", "--spec", SpecSupport::SPEC_PATH, "--profile", SpecSupport::PROFILE_PATH, "--defaults", SpecSupport::DEFAULTS_PATH, "--output", directory)
      expect(status.success?).to be(true), "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      expect(File).to exist(File.join(directory, "provider_blueprint.json"))
      expect(JSON.parse(File.read(File.join(directory, "provider_blueprint.json"))).fetch("decision")).to eq("ACCEPT")

      stdout, stderr, status = Open3.capture3(RbConfig.ruby, SpecSupport::BIN_PATH, "verify", "--output", directory)
      expect(status.success?).to be(true), "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      expect(JSON.parse(stdout).fetch("passed")).to be(true)
    end
  end
end
