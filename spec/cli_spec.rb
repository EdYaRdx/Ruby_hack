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
    expect(ProviderCompiler::CLI.default_options.fetch(:defaults)).to eq("fixtures/empty_case_defaults.yml")
    expect(ProviderCompiler::CLI.default_options.fetch(:defaults_origin)).to eq("none")
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

  it "keeps unresolved analyze output machine-readable without runtime artifacts" do
    Dir.mktmpdir("provider-cli-analyze") do |directory|
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        SpecSupport::BIN_PATH,
        "analyze",
        "--spec", SpecSupport::SPEC_PATH,
        "--profile", SpecSupport::PROFILE_PATH,
        "--out", directory
      )

      expect(status.success?).to be(true), "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      summary = JSON.parse(stdout)
      expect(summary).to include("decision" => "REVIEW_REQUIRED", "generation_ready" => false)
      expect(summary.fetch("blocking")).to be > 0
      expect(Dir.children(directory)).to contain_exactly("provider_blueprint.json", "review_manifest.json")
    end
  end

  it "fails closed for unresolved generate without deleting unrelated output" do
    Dir.mktmpdir("provider-cli-generate") do |parent|
      directory = File.join(parent, "output")
      Dir.mkdir(directory)
      File.write(File.join(directory, "keep.txt"), "user file\n")
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        SpecSupport::BIN_PATH,
        "generate",
        "--spec", SpecSupport::SPEC_PATH,
        "--profile", SpecSupport::PROFILE_PATH,
        "--out", directory
      )

      expect(status.success?).to be(false), "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      expect(File).to exist(File.join(directory, "keep.txt"))
      expect(Dir.children(directory)).to contain_exactly("keep.txt", "provider_blueprint.json", "review_manifest.json", "INTEGRATION.md")
      expect(File).not_to exist(File.join(directory, "service.rb"))
    end
  end

  it "removes stale runtime and readiness artifacts when analyze follows generate" do
    Dir.mktmpdir("provider-cli-stale") do |directory|
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        SpecSupport::BIN_PATH,
        "generate",
        "--spec", SpecSupport::SPEC_PATH,
        "--profile", SpecSupport::PROFILE_PATH,
        "--defaults", SpecSupport::DEFAULTS_PATH,
        "--out", directory
      )
      expect(status.success?).to be(true), "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      expect(File).to exist(File.join(directory, "service.rb"))
      expect(File).to exist(File.join(directory, "integration_readiness.json"))
      expect(File).to exist(File.join(directory, "INTEGRATION_READINESS.md"))

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        SpecSupport::BIN_PATH,
        "analyze",
        "--spec", SpecSupport::SPEC_PATH,
        "--profile", SpecSupport::PROFILE_PATH,
        "--out", directory
      )
      expect(status.success?).to be(true), "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      expect(Dir.children(directory)).to contain_exactly("provider_blueprint.json", "review_manifest.json")
    end
  end

  it "compiles an explicit resolved provider in one command and reports provenance" do
    Dir.mktmpdir("provider-cli-compile") do |directory|
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        SpecSupport::BIN_PATH,
        "compile",
        "--spec", SpecSupport::SPEC_PATH,
        "--profile", SpecSupport::PROFILE_PATH,
        "--defaults", SpecSupport::DEFAULTS_PATH,
        "--out", directory
      )

      expect(status.exitstatus).to eq(0), "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      expect(stdout).to include("Decision: ACCEPT", "Provenance:", "Verification: PASS", "Result: READY")
      expect(File).to exist(File.join(directory, "service.rb"))
      expect(File).to exist(File.join(directory, "fixtures.json"))
      expect(File).to exist(File.join(directory, "integration_readiness.json"))
    end
  end

  it "compiles explicit spec-only input without implicit NovaPay defaults and blocks runtime output" do
    Dir.mktmpdir("provider-cli-compile-review") do |directory|
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        SpecSupport::BIN_PATH,
        "compile",
        "--spec", File.join(SpecSupport::ROOT, "fixtures", "aurora_transfer_api.yaml"),
        "--profile", File.join(SpecSupport::ROOT, "profiles", "aurora_payments_v1.yml"),
        "--out", directory
      )

      expect(status.exitstatus).to eq(2), "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      expect(stdout).to include("Decision: REVIEW_REQUIRED", "case_default=0", "Result: GENERATION_BLOCKED")
      expect(File).to exist(File.join(directory, "provider_blueprint.json"))
      expect(File).to exist(File.join(directory, "review_manifest.json"))
      expect(File).not_to exist(File.join(directory, "service.rb"))
      expect(File).not_to exist(File.join(directory, "fixtures.json"))
      expect(File).not_to exist(File.join(directory, "contract_smoke.rb"))
    end
  end

  it "compiles PROVIDER_SPEC input without implicit NovaPay defaults" do
    Dir.mktmpdir("provider-cli-env-review") do |directory|
      custom_spec = File.join(SpecSupport::ROOT, "fixtures", "aurora_transfer_api.yaml")
      custom_profile = File.join(SpecSupport::ROOT, "profiles", "aurora_payments_v1.yml")
      stdout, stderr, status = Open3.capture3(
        { "PROVIDER_SPEC" => custom_spec },
        RbConfig.ruby,
        SpecSupport::BIN_PATH,
        "compile",
        "--profile", custom_profile,
        "--out", directory
      )

      expect(status.exitstatus).to eq(2), "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      expect(stdout).to include("Decision: REVIEW_REQUIRED", "case_default=0", "Result: GENERATION_BLOCKED")
      expect(File).not_to exist(File.join(directory, "service.rb"))
    end
  end
end
