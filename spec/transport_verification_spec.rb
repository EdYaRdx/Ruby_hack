# frozen_string_literal: true

RSpec.describe ProviderCompiler::TransportVerification do
  it "verifies generated outbound requests through a real localhost HTTP socket" do
    pipeline = SpecSupport.pipeline

    Dir.mktmpdir("transport-verification") do |directory|
      ProviderCompiler::DeterministicGenerator.new.generate(
        pipeline.blueprint,
        pipeline.manifest,
        directory,
        examples: pipeline.defaults.examples,
        spec_document: pipeline.source_document.resolved
      )

      verification = ProviderCompiler::Verification.new.verify(directory)
      transport = verification.fetch("transport")

      expect(transport).to include("status" => "PASS", "method" => "localhost_http_e2e", "outbound_http_supported" => true)
      expect(transport.dig("create_request", "passed")).to be(true)
      expect(transport.dig("status_request", "passed")).to be(true)
      expect(transport.dig("response_parsing", "passed")).to be(true)
      expect(transport.dig("external_provider_call", "executed")).to be(false)
      expect(transport.dig("requests", "create")).to include("method" => "POST", "path" => "/payouts")
      expect(transport.dig("requests", "status", "method")).to eq("GET")
      expect(transport.dig("requests", "status", "path")).to match(%r{\A/payouts/[^/]+\z})
      expect(transport.dig("requests", "create", "headers").values.flatten).not_to include("transport-verification-key")
      expect(transport.fetch("checks").map { |item| item.fetch("name") }).to include(
        "create.method", "create.path", "create.query", "create.auth", "create.body", "create.content_type",
        "status.method", "status.path", "status.auth", "response.parsing", "response.status_mapping"
      )
    end
  end
end
