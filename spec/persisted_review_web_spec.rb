# frozen_string_literal: true

require "webrick"
require "provider_compiler/web"

RSpec.describe "persisted Review actions in the Web workbench" do
  class PersistedReviewFakeRequest
    attr_reader :request_method, :path, :body, :header

    def initialize(method, path, body: "", content_type: "application/x-www-form-urlencoded")
      @request_method = method
      @path = path.split("?", 2).first
      @body = body
      @header = { "content-type" => [content_type] }
    end

    def query
      WEBrick::HTTPUtils.parse_query("")
    end
  end

  class PersistedReviewFakeResponse
    attr_accessor :status, :body
    attr_reader :headers

    def initialize
      @status = 200
      @body = ""
      @headers = {}
    end

    def [](name)
      @headers[name]
    end

    def []=(name, value)
      @headers[name] = value
    end
  end

  let(:store) { ProviderCompiler::Web::WorkspaceStore.new }
  let(:app) { ProviderCompiler::Web::Application.new(store: store) }

  after do
    store.cleanup
  end

  def call(method, path, body: "", content_type: "application/x-www-form-urlencoded")
    request = PersistedReviewFakeRequest.new(method, path, body: body, content_type: content_type)
    response = PersistedReviewFakeResponse.new
    app.call(request, response)
    response
  end

  def workspace_id(response)
    response.headers.fetch("Location")[%r{/workspace/([a-f0-9]+)/}, 1]
  end

  def multipart_override(yaml)
    boundary = "----provider-compiler-review-test"
    body = "--#{boundary}\r\n" \
      "Content-Disposition: form-data; name=\"override_file\"; filename=\"provider_overrides.yml\"\r\n" \
      "Content-Type: application/yaml\r\n\r\n#{yaml}\r\n" \
      "--#{boundary}--\r\n"
    [body, "multipart/form-data; boundary=#{boundary}"]
  end

  it "exports a human decision and imports it into another workspace" do
    source_response = call("POST", "/demo", body: "demo=novapay_spec_only")
    source_id = workspace_id(source_response)
    source = store.fetch(source_id)
    source.resolve!(
      "money:amount-units",
      "provider_unit" => "minor", "provider_subunit" => "kopecks", "scale" => "100"
    )

    export = call("GET", "/workspace/#{source_id}/review/export")
    expect(export.status).to eq(200)
    expect(export.headers.fetch("Content-Disposition")).to include("provider_overrides.yml")
    expect(export.body).to include("schema_version: 1", "HUMAN_CONFIRMED", "spec_fingerprint")
    expect(export.body).not_to match(/api[_-]?key|secret|password|credential/i)

    target_response = call("POST", "/demo", body: "demo=novapay_spec_only")
    target_id = workspace_id(target_response)
    body, content_type = multipart_override(export.body)
    imported = call("POST", "/workspace/#{target_id}/review/import", body: body, content_type: content_type)

    expect(imported.status).to eq(303)
    target = store.fetch(target_id)
    expect(target.manifest.to_h.dig("review_override", "status")).to eq("APPLIED")
    expect(target.blueprint.dig("money", "provider", "unit")).to eq("minor")
  end
end
