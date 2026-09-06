# frozen_string_literal: true

RSpec.describe ProviderCompiler::IntegrationReadiness do
  it "builds a machine-readable readiness report from actual pipeline and verification data" do
    pipeline = SpecSupport.pipeline
    Dir.mktmpdir("readiness") do |directory|
      ProviderCompiler::DeterministicGenerator.new.generate(pipeline.blueprint, pipeline.manifest, directory, examples: pipeline.defaults.examples, spec_document: pipeline.source_document.resolved)
      verification = ProviderCompiler::Verification.new.verify(directory)
      report = described_class.build(pipeline, generated: true, verification: verification)
      described_class.write(directory, report)

      expect(report).to include("spec_fingerprint" => pipeline.source_document.fingerprint, "generated" => true)
      expect(report.dig("decisions", "counts")).to include("blocking_count" => 0, "review_count" => 0)
      expect(report.dig("operations", "found")).to be > 0
      expect(report.dig("semantics", "money", "host", "unit")).to eq("major")
      expect(report.dig("runtime_transport", "status")).to eq("PASS")
      expect(report.dig("runtime_transport", "method")).to eq("localhost_http_e2e")
      expect(report.dig("runtime_transport", "create_request", "passed")).to be(true)
      expect(report.dig("runtime_transport", "status_request", "passed")).to be(true)
      expect(report.dig("runtime_transport", "external_provider_call", "executed")).to be(false)
      expect(JSON.parse(File.read(File.join(directory, "integration_readiness.json"))).fetch("ready")).to be(true)
      expect(File.read(File.join(directory, "INTEGRATION_READINESS.md"), encoding: "UTF-8")).to include("Integration Readiness", "Human decisions supplied", "Runtime transport", "localhost_http_e2e", "NOT_EXECUTED")
    end
  end
end
