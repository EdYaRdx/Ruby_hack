# frozen_string_literal: true

require "yaml"
require "provider_compiler/web"
require_relative "support/organizer_contract_harness"

RSpec.describe "Goal 5 spec-only hardening and generator correctness" do
  let(:root) { SpecSupport::ROOT }
  let(:helios_spec) { File.join(root, "fixtures", "heliospay_transfer_api.yaml") }
  let(:helios_profile) { File.join(root, "profiles", "heliospay_payments_v1.yml") }
  let(:helios_defaults) { File.join(root, "fixtures", "heliospay_case_defaults.yml") }
  let(:empty_defaults) { File.join(root, "fixtures", "empty_case_defaults.yml") }

  def pipeline_for(spec_path, profile_path, defaults_path)
    ProviderCompiler::Pipeline.new(spec_path: spec_path, profile_path: profile_path, defaults_path: defaults_path)
  end

  def generate_for(pipeline, directory, examples: pipeline.defaults.examples)
    ProviderCompiler::DeterministicGenerator.new.generate(
      pipeline.blueprint,
      pipeline.manifest,
      directory,
      examples: examples,
      spec_document: pipeline.source_document.resolved
    )
  end

  def load_generated_service(directory, blueprint)
    class_name = "#{ProviderCompiler::Util.camel(blueprint.dig("provider", "name"))}Service"
    Provider.send(:remove_const, class_name) if Provider.const_defined?(class_name, false)
    load File.join(directory, "service.rb")
    Provider.const_get(class_name)
  end

  it "extracts HeliosPay money, nested mappings and documented success codes from spec-only input" do
    pipeline = pipeline_for(helios_spec, helios_profile, empty_defaults)
    blueprint = pipeline.blueprint

    expect(blueprint.dig("money", "decision")).to eq("ACCEPT")
    expect(blueprint.dig("money", "provider")).to include(
      "field" => "request.payment.amount",
      "response_field" => "response.settlement.amount",
      "unit" => "minor",
      "subunit" => "cents",
      "scale" => 100,
      "scale_source" => "SPEC_FACT"
    )
    expect(blueprint.dig("money", "provider", "evidence_sources")).not_to include("CASE_DEFAULT")
    expect(blueprint.fetch("endpoints").find { |item| item["canonical"] == "create_request" }).to include("success_statuses" => ["202"])
    expect(blueprint.fetch("extra_operations")).to include(include("path" => "/account/limits", "kind" => "EXTRA_OPERATION", "blocking" => false))
    expect(blueprint.fetch("decision")).to eq("REVIEW_REQUIRED")
  end

  it "uses a documented 202 response and accepts bodyless 204 responses" do
    pipeline = pipeline_for(helios_spec, helios_profile, helios_defaults)
    expect(pipeline.blueprint.fetch("decision")).to eq("ACCEPT")

    Dir.mktmpdir("helios-202") do |directory|
      generate_for(pipeline, directory)
      service_class = load_generated_service(directory, pipeline.blueprint)
      client = Class.new do
        def request(_method, _url, _headers, _body, _query)
          { "http_status" => 202, "body" => { "fund_id" => "hf-202", "phase" => "initiated", "settlement" => { "amount" => 1250, "currency" => "EUR" } } }
        end
      end.new
      result = service_class.new(api_key: "key", client: client).create_request(pipeline.defaults.examples.dig("create_request", "operation"))
      expect(result).to include("ok" => true, "http_status" => "202", "status" => "in_progress")
    end

    spec = YAML.safe_load(File.read(helios_spec, encoding: "UTF-8"), aliases: true)
    response = spec.dig("paths", "/funds", "post", "responses").delete("202")
    spec.dig("paths", "/funds", "post", "responses")["204"] = response.merge("description" => "Fund accepted without a response body").reject { |key, _value| key == "content" }
    Dir.mktmpdir("helios-204") do |directory|
      spec_path = File.join(directory, "provider_api.yaml")
      File.write(spec_path, YAML.dump(spec), encoding: "UTF-8")
      mutated = pipeline_for(spec_path, helios_profile, helios_defaults)
      expect(mutated.blueprint.fetch("endpoints").find { |item| item["canonical"] == "create_request" }.fetch("success_statuses")).to eq(["204"])
      generate_for(mutated, directory)
      service_class = load_generated_service(directory, mutated.blueprint)
      client = Class.new do
        def request(_method, _url, _headers, _body, _query)
          { "http_status" => 204 }
        end
      end.new
      result = service_class.new(api_key: "key", client: client).create_request(mutated.defaults.examples.dig("create_request", "operation"))
      expect(result).to include("ok" => true, "http_status" => "204", "response" => nil)
    end
  end

  it "projects Blueprint error categories, raw details and Retry-After into runtime failures" do
    pipeline = pipeline_for(File.join(root, "fixtures", "novapay_provider_api.yaml"), File.join(root, "profiles", "space_payments_v1.yml"), File.join(root, "fixtures", "novapay_case_defaults.yml"))
    Dir.mktmpdir("novapay-errors") do |directory|
      generate_for(pipeline, directory)
      service_class = load_generated_service(directory, pipeline.blueprint)
      operation = pipeline.defaults.examples.dig("create_request", "operation")
      cases = {
        400 => [nil, "validation_error"],
        401 => ["unauthorized", "unauthorized"],
        402 => ["insufficient_balance", "insufficient_balance"],
        409 => ["provider_duplicate", "conflict"],
        422 => ["validation_error", "validation_error"],
        429 => ["rate_limit_exceeded", "rate_limit_exceeded"],
        500 => ["provider_new_error", "internal_error"]
      }
      cases.each do |status, (code, category)|
        response = { "http_status" => status, "body" => { "error" => { "code" => code, "message" => "provider detail", "details" => { "trace" => "raw-#{status}" } } } }
        response["headers"] = { "Retry-After" => "7" } if status == 429
        client = Class.new do
          def initialize(value)
            @value = value
          end

          def request(*_args)
            @value
          end
        end.new(response)
        result = service_class.new(api_key: "key", client: client).create_request(operation)
        expect(result).to include("ok" => false, "http_status" => status.to_s, "error_category" => category)
        expect(result.fetch("error")).to include("message" => "provider detail")
        expect(result.fetch("retry_after")).to eq("7") if status == 429
      end
    end
  end

  it "follows the profile-driven BaseService super and failure contract" do
    pipeline = pipeline_for(File.join(root, "fixtures", "novapay_provider_api.yaml"), File.join(root, "profiles", "space_payments_v1.yml"), File.join(root, "fixtures", "novapay_case_defaults.yml"))
    Dir.mktmpdir("organizer-contract") do |directory|
      generate_for(pipeline, directory)
      OrganizerContractHarness.with_base_service do
        service_class = load_generated_service(directory, pipeline.blueprint)
        service = service_class.new(api_key: "key")
        valid = pipeline.defaults.examples.dig("create_request", "operation")
        expect(service.check_conditions(valid, "create")).to include("ok" => true)
        expect(service.base_check_calls).to eq(1)
        blocked = service.check_conditions(valid.merge("base_blocked" => true), "create")
        expect(blocked).to include("ok" => false, "error_code" => "base_blocked")
        invalid = valid.merge("recipient" => { "type" => "sbp", "phone" => "79001234567" })
        expect(service.check_conditions(invalid, "create")).to include("ok" => false, "http_status" => 422, "error_code" => "validation_error")
        expect(service.failure_calls.last).to include(422, "validation_error")

        non_create = service.check_conditions(invalid, "status")
        expect(non_create).to include("ok" => true)
        expect(service.base_check_calls).to eq(4)
        non_create_blocked = service.check_conditions(valid.merge("base_blocked" => true), "status")
        expect(non_create_blocked).to include("ok" => false, "error_code" => "base_blocked")
        expect(service.base_check_calls).to eq(5)
      end
    end
  end

  it "synthesizes fixtures from OpenAPI examples before fallback examples and records provenance" do
    pipeline = pipeline_for(helios_spec, helios_profile, helios_defaults)
    fallback = { "create_request" => { "operation" => { "amount" => 9999, "currency" => "EUR", "external_id" => "fallback" } } }
    Dir.mktmpdir("fixture-provenance") do |directory|
      generate_for(pipeline, directory, examples: fallback)
      fixtures = JSON.parse(File.read(File.join(directory, "fixtures.json"), encoding: "UTF-8"))
      expect(fixtures.dig("create_request", "operation", "amount")).to eq(12.5)
      expect(fixtures.dig("fixture_provenance", "create_request")).to eq("SPEC_EXAMPLE")
      expect(fixtures.dig("fixture_provenance", "process_callback")).to eq("SPEC_EXAMPLE")
    end
  end

  it "uses resolved Blueprint and fixtures for NovaPay, Aurora and HeliosPay previews" do
    store = ProviderCompiler::Web::WorkspaceStore.new
    begin
      {
        "novapay" => [1500.5, "approved"],
        "aurora_resolved" => [1500.5, "approved"],
        "heliospay" => [1500.5, "approved"]
      }.each do |demo, (expected_amount, expected_status)|
        workspace = store.create_demo(demo)
        expect(workspace.accepted?).to be(true), "#{demo} was not resolved"
        request = workspace.preview!("request", "amount" => "1500.50")
        response = workspace.preview!("response")
        webhook = workspace.preview!("webhook")
        provider_body = request.dig("provider_request", "body")
        expect(provider_body).not_to be_empty
        expect(response.dig("host_result", "amount").to_f).to eq(expected_amount.to_f)
        expect(response.dig("host_result", "status")).to eq(expected_status)
        expect(webhook.dig("result", "ok")).to be(true)
      end
    ensure
      store.cleanup
    end
  end

  it "keeps generic request preview free of NovaPay literals" do
    source = File.read(File.join(root, "lib", "provider_compiler", "web_renderer.rb"), encoding: "UTF-8")
    preview_method = source[/def request_preview\(workspace, result\).*?\n      def response_preview/m]

    expect(preview_method).not_to be_nil
    expect(preview_method).not_to include("NovaPay", "np-demo", "payout.completed", "X-NovaPay", "RUB", "kopecks")
  end

  it "renders resolved HTTP error categories instead of repeating a global provider enum" do
    pipeline = pipeline_for(File.join(root, "fixtures", "novapay_provider_api.yaml"), File.join(root, "profiles", "space_payments_v1.yml"), File.join(root, "fixtures", "novapay_case_defaults.yml"))
    Dir.mktmpdir("generated-docs") do |directory|
      generate_for(pipeline, directory)
      doc = File.read(File.join(directory, "INTEGRATION.md"), encoding: "UTF-8")
      expect(doc).to match(/HTTP 401: .*unauthorized/)
      expect(doc).to match(/HTTP 402: .*insufficient_balance/)
      expect(doc).to match(/HTTP 429: .*rate_limit_exceeded.*Retry-After/)
      expect(doc).to match(/HTTP 500: .*internal_error/)
      expect(doc).not_to match(/HTTP 401: .*insufficient_balance/)
      expect(doc).to include("## Маппинг статусов", "## ProviderGateway / конфигурация")
      pipeline.blueprint.fetch("statuses").each do |item|
        expect(doc).to include("| `#{item.fetch("provider_value")}` | `#{item.fetch("canonical_value")}` |")
      end
      expect(doc).to include("NOVAPAY_BASE_URL", "X-API-Key", "Idempotency-Key")
    end
  end

  it "keeps integration documentation generation provider-neutral" do
    source = File.read(File.join(root, "lib", "provider_compiler", "generation.rb"), encoding: "UTF-8")

    expect(source).not_to include("NovaPay", "novapay", "payouts", "X-NovaPay")
  end
end
