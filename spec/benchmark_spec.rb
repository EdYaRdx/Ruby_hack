# frozen_string_literal: true

require "yaml"
require_relative "../research/benchmark/run"

RSpec.describe "real mutation benchmark regression semantics" do
  let(:source) { YAML.safe_load(File.read(RealMutationBenchmark::SOURCE_PATH, encoding: "UTF-8"), aliases: true) }

  def with_mutation(id)
    document, extra_files = RealMutationBenchmark::Mutator.new(source).apply(id)
    Dir.mktmpdir("mutation-regression") do |directory|
      spec_path = File.join(directory, "provider_api.yaml")
      File.write(spec_path, YAML.dump(document), encoding: "UTF-8")
      extra_files.each { |name, content| File.write(File.join(directory, name), YAML.dump(content), encoding: "UTF-8") }
      yield ProviderCompiler::Pipeline.new(spec_path: spec_path, profile_path: SpecSupport::PROFILE_PATH, defaults_path: SpecSupport::DEFAULTS_PATH)
    end
  end

  it "reviews conflicting operation identity evidence and accepts structural identity without operationId" do
    with_mutation("M01") do |pipeline|
      item = pipeline.blueprint.fetch("endpoints").find { |endpoint| endpoint["operation_id"] == "createPayout" }
      expect(item.fetch("decision")).to eq("REVIEW_REQUIRED")
    end

    with_mutation("M05") do |pipeline|
      item = pipeline.blueprint.fetch("operations").find { |operation| operation["path"] == "/payouts" }
      expect(item.fetch("canonical")).to eq("create_request")
      expect(pipeline.blueprint.fetch("decision")).to eq("ACCEPT")
    end
  end

  it "preserves unknown extra endpoints without turning them into a blocking review" do
    with_mutation("M30") do |pipeline|
      extra = pipeline.blueprint.fetch("extra_operations").find { |operation| operation["path"] == "/limits" }
      expect(extra).to include("kind" => "EXTRA_OPERATION", "preserved" => true, "blocking" => false)
      expect(pipeline.blueprint.fetch("decision")).to eq("ACCEPT")
    end
  end

  it "does not accept renamed or nested money fields from provider defaults" do
    %w[M08 M09 M10].each do |id|
      with_mutation(id) do |pipeline|
        expect(pipeline.blueprint.dig("money", "decision")).to eq("REVIEW_REQUIRED")
        expect(pipeline.blueprint.fetch("decision")).to eq("REVIEW_REQUIRED")
      end
    end
  end

  it "does not retain a resolved money conversion when unit evidence conflicts" do
    with_mutation("M12") do |pipeline|
      money = pipeline.blueprint.fetch("money")
      expect(money.fetch("decision")).to eq("REVIEW_REQUIRED")
      expect(money.dig("request_conversion", "status")).to eq("unresolved")
      expect(money.dig("response_conversion", "status")).to eq("unresolved")
    end
  end

  it "reviews absent idempotency semantics and does not invent retry safety" do
    with_mutation("M23") do |pipeline|
      idempotency = pipeline.blueprint.fetch("idempotency")
      expect(idempotency.fetch("header")).to be_nil
      expect(idempotency.dig("retry_policy", "name")).to eq("unknown")
      expect(pipeline.blueprint.fetch("decision")).to eq("REVIEW_REQUIRED")
    end
  end

  it "distinguishes plausible status synonyms from an unknown terminal status" do
    with_mutation("M14") do |pipeline|
      expect(pipeline.blueprint.fetch("decision")).to eq("REVIEW_REQUIRED")
    end
    with_mutation("M18") do |pipeline|
      expect(pipeline.blueprint.fetch("decision")).to eq("UNKNOWN")
    end
  end

  it "accepts polling-only providers and discovers callback/top-level webhook forms" do
    with_mutation("M28") do |pipeline|
      expect(pipeline.blueprint.dig("webhook", "mode")).to eq("polling_only")
      expect(pipeline.blueprint.fetch("decision")).to eq("ACCEPT")
      expect { pipeline.validate_blueprint! }.not_to raise_error
    end
    %w[M26 M27].each do |id|
      with_mutation(id) do |pipeline|
        expect(pipeline.blueprint.dig("webhook", "decision")).to eq("ACCEPT")
      end
    end
  end

  it "keeps ambiguous transaction endpoints unresolved" do
    with_mutation("M35") do |pipeline|
      expect(pipeline.blueprint.fetch("decision")).to eq("UNKNOWN")
    end
  end

  it "does not mistake an unbound void action for a create operation" do
    with_mutation("M32") do |pipeline|
      operation = pipeline.blueprint.fetch("endpoints").find { |item| item["operation_id"] == "voidPayout" }
      expect(operation.fetch("decision")).to eq("ACCEPT")
      expect(pipeline.blueprint.fetch("decision")).to eq("ACCEPT")
    end
  end
end
