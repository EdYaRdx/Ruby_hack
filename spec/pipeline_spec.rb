# frozen_string_literal: true

RSpec.describe "NovaPay ingestion and immutable Facts IR" do
  it "loads, validates, resolves local refs and fingerprints the resolved closure" do
    pipeline = SpecSupport.pipeline
    source = pipeline.source_document

    expect(source.fingerprint).to match(/\Asha256:[0-9a-f]{64}\z/)
    expect(source.root_sha256).to eq("415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551")
    refs = source.resolved_refs.map { |item| item["ref"] }
    expect(refs).to include("#/components/schemas/CreatePayoutRequest", "#/components/schemas/Recipient", "#/components/parameters/IdempotencyKey")
    expect(source.to_h.fetch("fingerprint_inputs").fetch("resolved_local_ref_closure")).not_to be_empty
  end

  it "keeps the resolved source and Facts IR immutable" do
    pipeline = SpecSupport.pipeline

    expect(pipeline.source_document.resolved.frozen?).to be(true)
    expect(pipeline.facts.operations).to all(be_frozen)
    expect { pipeline.source_document.resolved.fetch("paths")["/payouts"] = {} }.to raise_error(FrozenError)
    expect { pipeline.facts.operations << :new_operation }.to raise_error(FrozenError)
  end

  it "discovers the five provider endpoints without the old status operationId" do
    operations = SpecSupport.pipeline.facts.operations

    expect(operations.length).to eq(5)
    expect(operations.map { |item| item["operation_id"] }).to include("createPayout", "getPayoutStatus", "cancelPayout", "payoutWebhook", "getBalance")
    expect(operations.map { |item| item["operation_id"] }).not_to include("getPayout")
  end

  it "supports allowlisted local external refs and includes them in the fingerprint" do
    Dir.mktmpdir("provider-refs") do |directory|
      root = File.join(directory, "api.yml")
      components = File.join(directory, "components.yml")
      File.write(components, "components:\n  schemas:\n    Ping:\n      type: object\n      properties:\n        ok:\n          type: boolean\n")
      File.write(root, "openapi: 3.0.3\ninfo:\n  title: External Ref API\n  version: 1.0.0\npaths:\n  /ping:\n    get:\n      operationId: ping\n      responses:\n        '200':\n          description: ok\n          content:\n            application/json:\n              schema:\n                $ref: components.yml#/components/schemas/Ping\n")

      first = ProviderCompiler::OpenAPILoader.new(root).load
      expect(first.resolved_refs.first.fetch("target_file")).to eq("components.yml")
      expect(first.loaded_files.keys).to include("api.yml", "components.yml")
      first_fingerprint = first.fingerprint
      File.write(components, "components:\n  schemas:\n    Ping:\n      type: object\n      properties:\n        ok:\n          type: string\n")
      second_fingerprint = ProviderCompiler::OpenAPILoader.new(root).load.fingerprint
      expect(second_fingerprint).not_to eq(first_fingerprint)
    end
  end

  it "loads JSON and rejects invalid OpenAPI before analysis" do
    Dir.mktmpdir("provider-json") do |directory|
      json_path = File.join(directory, "api.json")
      File.write(json_path, JSON.generate("openapi" => "3.0.3", "info" => { "title" => "JSON API", "version" => "1.0.0" }, "paths" => { "/ping" => { "get" => { "operationId" => "ping", "responses" => { "200" => { "description" => "ok" } } } } }))
      source = ProviderCompiler::OpenAPILoader.new(json_path).load
      expect { ProviderCompiler::OpenAPIValidator.new.validate!(source) }.not_to raise_error

      invalid_path = File.join(directory, "invalid.json")
      File.write(invalid_path, JSON.generate("openapi" => "2.0", "info" => { "title" => "Invalid", "version" => "1.0.0" }, "paths" => {}))
      invalid_source = ProviderCompiler::OpenAPILoader.new(invalid_path).load
      expect { ProviderCompiler::OpenAPIValidator.new.validate!(invalid_source) }.to raise_error(ProviderCompiler::ValidationError)
    end
  end
end
