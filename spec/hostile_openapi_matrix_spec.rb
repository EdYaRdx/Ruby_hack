# frozen_string_literal: true

require "json"
require "tmpdir"

RSpec.describe "hostile OpenAPI matrix" do
  def base_document
    {
      "openapi" => "3.0.3",
      "info" => { "title" => "Matrix API", "version" => "1" },
      "components" => { "securitySchemes" => { "Key" => { "type" => "apiKey", "in" => "header", "name" => "X-Key" } } },
      "paths" => {
        "/transfers" => {
          "post" => {
            "operationId" => "createTransfer",
            "security" => [{ "Key" => [] }],
            "requestBody" => { "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "amount" => { "type" => "number", "description" => "major units" } } } } } },
            "responses" => { "201" => { "description" => "created" } }
          }
        }
      }
    }
  end

  it "keeps hostile and unusual OpenAPI shapes inside explicit compiler outcomes" do
    cases = {}
    cases["invalid_version"] = base_document.merge("openapi" => "2.0")
    cases["paths_wrong_type"] = base_document.merge("paths" => [])
    cases["malformed_operation"] = base_document.merge("paths" => { "/x" => { "post" => "not-an-operation" } })
    cases["missing_schema"] = base_document.tap { |d| d["paths"]["/transfers"]["post"]["requestBody"]["content"]["application/json"].delete("schema") }
    cases["giant_description"] = base_document.tap { |d| d["info"]["description"] = "x" * 250_000 }
    cases["deep_schema"] = base_document.tap do |d|
      node = { "type" => "object", "properties" => {} }
      70.times { node = { "type" => "object", "properties" => { "nested" => node } } }
      d["components"]["schemas"] = { "Deep" => node }
    end
    cases["unsupported_content"] = base_document.tap { |d| d["paths"]["/transfers"]["post"]["requestBody"]["content"] = { "application/xml" => { "schema" => { "type" => "object" } } } }
    cases["server_variables"] = base_document.merge("servers" => [{ "url" => "https://{region}.example/{version}", "variables" => { "region" => { "default" => "sandbox" }, "version" => { "default" => "v1" } } }])
    cases["cookie_parameter"] = base_document.tap { |d| d["paths"]["/transfers"]["post"]["parameters"] = [{ "name" => "tenant", "in" => "cookie", "required" => false, "schema" => { "type" => "string" } }] }
    cases["duplicate_semantic_operations"] = base_document.tap { |d| d["paths"]["/transfers"]["post"]["operationId"] = "createTransferAgain"; d["paths"]["/second"] = d["paths"]["/transfers"] }
    cases["many_operations"] = base_document.tap { |d| 60.times { |i| d["paths"]["/extra#{i}"] = { "get" => { "operationId" => "extra#{i}", "responses" => { "200" => { "description" => "ok" } } } } } }
    cases["unicode_text"] = base_document.tap { |d| d["info"]["description"] = "Платёж ✅ <script>alert(1)</script>" }
    cases["invalid_pattern"] = base_document.tap { |d| d["paths"]["/transfers"]["post"]["requestBody"]["content"]["application/json"]["schema"]["properties"]["amount"]["pattern"] = "[" }

    Dir.mktmpdir("hostile-matrix") do |directory|
      unexpected = []
      cases.each do |id, document|
        path = File.join(directory, "#{id}.yaml")
        File.write(path, YAML.dump(document), encoding: "UTF-8")
        begin
          pipeline = ProviderCompiler::Pipeline.new(spec_path: path, profile_path: SpecSupport::PROFILE_PATH, defaults_path: File.join(SpecSupport::ROOT, "fixtures", "empty_case_defaults.yml"))
          unexpected << "#{id}: invalid decision" unless %w[ACCEPT REVIEW_REQUIRED UNKNOWN].include?(pipeline.blueprint["decision"])
        rescue ProviderCompiler::Error, ProviderCompiler::ValidationError
          # Explicit rejection is a safe outcome for hostile input.
        rescue StandardError => e
          unexpected << "#{id}: #{e.class}: #{e.message}"
        end
      end
      expect(unexpected).to eq([])
    end
  end

  it "rejects remote references and invalid JSON pointers without network access" do
    Dir.mktmpdir("hostile-json-ref") do |directory|
      remote = <<~YAML
        openapi: 3.0.3
        info: { title: Remote, version: '1' }
        paths:
          /x:
            get:
              responses:
                '200': { description: ok, content: { application/json: { schema: { $ref: 'https://provider.example/schema.yaml#/Thing' } } } }
      YAML
      broken_pointer = remote.gsub("https://provider.example/schema.yaml#/Thing", "local.yaml#/missing")
      File.write(File.join(directory, "remote.yaml"), remote, encoding: "UTF-8")
      File.write(File.join(directory, "pointer.yaml"), broken_pointer, encoding: "UTF-8")
      expect { ProviderCompiler::OpenAPILoader.new(File.join(directory, "remote.yaml")).load }.to raise_error(ProviderCompiler::RefError, /remote/) 
      expect { ProviderCompiler::OpenAPILoader.new(File.join(directory, "pointer.yaml")).load }.to raise_error(ProviderCompiler::RefError, /cannot read|unresolved/)
    end
  end
end
