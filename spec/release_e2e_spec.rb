# frozen_string_literal: true

require "json"
require "net/http"
require "webrick"

RSpec.describe "release-grade generated adapter E2E" do
  class ReleaseNetHttpClient
    def request(method, url, headers, body, query)
      uri = URI.parse(url)
      pairs = URI.decode_www_form(uri.query.to_s) + Array(query).map { |key, value| [key.to_s, value.to_s] }
      uri.query = URI.encode_www_form(pairs) unless pairs.empty?
      request_class = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post }.fetch(method)
      request = request_class.new(uri)
      headers.each { |key, value| request[key] = value.to_s }
      request.body = JSON.generate(body) if body
      response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }
      parsed = response.body.to_s.empty? ? nil : JSON.parse(response.body)
      { "http_status" => response.code.to_i, "headers" => response.each_header.to_h, "body" => parsed }
    end
  end

  def start_provider
    state = { "requests" => [] }
    server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
    server.mount_proc("/") do |request, response|
      body = request.body.to_s.empty? ? nil : JSON.parse(request.body)
      state["requests"] << {
        "method" => request.request_method,
        "path" => request.path,
        "query" => URI.decode_www_form(request.query_string.to_s).to_h,
        "headers" => request.header,
        "body" => body
      }
      marker = body && (body["external_id"] || body["client_reference"] || body["external_reference"])
      marker ||= request.path.split("/").last
      status = marker.to_s[/http-(\d+)/, 1]&.to_i
      if status
        response.status = status
        response["Retry-After"] = "7" if status == 429
        response["Content-Type"] = "application/json"
        response.body = JSON.generate("error" => { "message" => "synthetic HTTP #{status}" })
        next
      end

      if request.request_method == "POST" && request.path == "/payouts"
        if marker.to_s == "bodyless"
          response.status = 204
          response.body = ""
        else
          response.status = 201
          response["Content-Type"] = "application/json"
          response.body = JSON.generate("id" => "np-1", "status" => "pending", "amount" => 150_050, "currency" => "RUB")
        end
      elsif request.request_method == "GET" && request.path.start_with?("/payouts/")
        response.status = 200
        response["Content-Type"] = "application/json"
        response.body = JSON.generate("id" => "np-1", "status" => "completed", "amount" => 150_050, "currency" => "RUB")
      elsif request.request_method == "POST" && request.path == "/funds"
        response.status = 202
        response["Content-Type"] = "application/json"
        response.body = JSON.generate("fund_id" => "hf-1", "phase" => "initiated", "settlement" => { "amount" => 1250, "currency" => "EUR" })
      elsif request.request_method == "GET" && request.path.start_with?("/funds/")
        response.status = 200
        response["Content-Type"] = "application/json"
        response.body = JSON.generate("fund_id" => "hf-1", "phase" => "settled", "settlement" => { "amount" => 1250, "currency" => "EUR" })
      elsif request.request_method == "POST" && request.path == "/transfers"
        response.status = 201
        response["Content-Type"] = "application/json"
        response.body = JSON.generate("id" => "au-1", "status" => "queued", "money" => { "value" => "12.50", "currency" => "USD" })
      elsif request.request_method == "GET" && request.path.start_with?("/transfers/")
        response.status = 200
        response["Content-Type"] = "application/json"
        response.body = JSON.generate("id" => "au-1", "status" => "settled", "money" => { "value" => "12.50", "currency" => "USD" })
      elsif request.request_method == "POST" && request.path == "/payments"
        response.status = 200
        response["Content-Type"] = "application/json"
        response.body = JSON.generate("id" => "mi-1", "status" => "processing", "amount" => 1234)
      elsif request.request_method == "GET" && request.path.start_with?("/payments/")
        response.status = 200
        response["Content-Type"] = "application/json"
        response.body = JSON.generate("id" => "mi-1", "status" => "settled", "amount" => 1234)
      else
        response.status = 404
        response["Content-Type"] = "application/json"
        response.body = JSON.generate("error" => { "message" => "not found" })
      end
    end
    thread = Thread.new { server.start }
    100.times { break if server.status == :Running; sleep 0.01 }
    yield "http://127.0.0.1:#{server.config[:Port]}", state
  ensure
    server&.shutdown
    thread&.join
  end

  def with_env(name, value)
    previous = ENV[name]
    ENV[name] = value
    yield
  ensure
    previous.nil? ? ENV.delete(name) : ENV[name] = previous
  end

  def generated_service(pipeline, directory, blueprint: pipeline.blueprint)
    ProviderCompiler::DeterministicGenerator.new.generate(blueprint, pipeline.manifest, directory, examples: pipeline.defaults.examples, spec_document: pipeline.source_document.resolved)
    name = "#{ProviderCompiler::Util.camel(blueprint.dig("provider", "name"))}Service"
    Provider.send(:remove_const, name) if Provider.const_defined?(name, false)
    load File.join(directory, "service.rb")
    Provider.const_get(name)
  end

  def pipeline_for(spec, profile, defaults)
    ProviderCompiler::Pipeline.new(spec_path: spec, profile_path: profile, defaults_path: defaults)
  end

  it "runs generated artifacts through localhost HTTP across auth, success, transforms and statuses" do
    root = SpecSupport::ROOT
    nova = pipeline_for(File.join(root, "fixtures", "novapay_provider_api.yaml"), File.join(root, "profiles", "space_payments_v1.yml"), File.join(root, "fixtures", "novapay_case_defaults.yml"))
    helios = pipeline_for(File.join(root, "fixtures", "heliospay_transfer_api.yaml"), File.join(root, "profiles", "heliospay_payments_v1.yml"), File.join(root, "fixtures", "heliospay_case_defaults.yml"))
    aurora = pipeline_for(File.join(root, "fixtures", "aurora_transfer_api.yaml"), File.join(root, "profiles", "aurora_payments_v1.yml"), File.join(root, "fixtures", "aurora_case_defaults.yml"))

    start_provider do |base_url, state|
      Dir.mktmpdir("release-e2e") do |directory|
        with_env("NOVAPAY_BASE_URL", base_url) do
          nova_blueprint = ProviderCompiler::Util.deep_dup(nova.blueprint)
          nova_blueprint.fetch("endpoints").find { |item| item["canonical"] == "create_request" }.fetch("success_statuses") << "204"
          service = generated_service(nova, File.join(directory, "nova"), blueprint: nova_blueprint).new(api_key: "nova-key", webhook_secret: "secret", client: ReleaseNetHttpClient.new)
          operation = nova.defaults.examples.fetch("create_request").fetch("operation")
          created = service.create_request(operation.merge("external_id" => "nova-create"))
          expect(created).to include("ok" => true, "http_status" => "201", "status" => "in_progress")
          expect(state["requests"].find { |item| item["path"] == "/payouts" }.dig("headers", "x-api-key")).to eq(["nova-key"])
          expect(state["requests"].find { |item| item["path"] == "/payouts" }.dig("body", "amount")).to eq(1_500_000)

          fetched = service.fetch_status(provider_operation_id: "np-1")
          expect(fetched).to include("ok" => true, "http_status" => "200", "status" => "approved")
          bodyless = service.create_request(operation.merge("external_id" => "bodyless"))
          expect(bodyless).to include("ok" => true, "http_status" => "204")
        end

        with_env("HELIOSPAY_BASE_URL", base_url) do
          service = generated_service(helios, File.join(directory, "helios")).new(api_key: "helios-key", client: ReleaseNetHttpClient.new)
          operation = helios.defaults.examples.fetch("create_request").fetch("operation")
          created = service.create_request(operation)
          expect(created).to include("ok" => true, "http_status" => "202", "status" => "in_progress")
          helios_request = state["requests"].find { |item| item["path"] == "/funds" }
          expect(helios_request.fetch("query")).to include("access_token" => "helios-key")
          expect(helios_request.dig("body", "payment", "amount")).to eq(1250)
          expect(service.fetch_status(provider_operation_id: "hf-1")).to include("ok" => true, "status" => "approved", "amount" => 12.5)
        end

        with_env("AURORA_BASE_URL", base_url) do
          service = generated_service(aurora, File.join(directory, "aurora")).new(api_key: "aurora-key", client: ReleaseNetHttpClient.new)
          operation = { "amount" => "12.50", "currency" => "USD", "external_id" => "aurora-create", "recipient" => { "type" => "bank", "account" => "US123", "routing_number" => "011000015" } }
          expect(service.create_request(operation)).to include("ok" => true, "http_status" => "201", "status" => "in_progress")
          aurora_request = state["requests"].find { |item| item["path"] == "/transfers" }
          expect(aurora_request.dig("headers", "authorization")).to eq(["Bearer aurora-key"])
          expect(service.fetch_status(provider_operation_id: "au-1")).to include("ok" => true, "status" => "approved", "amount" => 12.5)
        end

        with_env("NOVAPAY_BASE_URL", base_url) do
          service = generated_service(nova, File.join(directory, "nova-errors")).new(api_key: "nova-key", client: ReleaseNetHttpClient.new)
          operation = nova.defaults.examples.fetch("create_request").fetch("operation")
          [400, 401, 404, 409, 422, 429, 500].each do |status|
            result = service.create_request(operation.merge("external_id" => "http-#{status}"))
            expect(result).to include("ok" => false, "http_status" => status.to_s)
            expect(result.fetch("error_category")).not_to be_nil
            expect(result.fetch("error_code")).to be_nil
          end
          limited = service.create_request(operation.merge("external_id" => "http-429"))
          expect(limited.fetch("retry_after")).to eq("7")
        end
      end
    end
  end

  it "covers generated webhook outcomes and stable idempotency across retry and restart" do
    pipeline = SpecSupport.pipeline
    start_provider do |base_url, state|
      with_env("NOVAPAY_BASE_URL", base_url) do
        Dir.mktmpdir("release-webhook") do |directory|
          service_class = generated_service(pipeline, directory)
          operation = pipeline.defaults.examples.fetch("create_request").fetch("operation").merge("idempotency_key" => "stable-key", "external_id" => "same-operation")
          first = service_class.new(api_key: "nova-key", webhook_secret: "secret", client: ReleaseNetHttpClient.new)
          second = service_class.new(api_key: "nova-key", webhook_secret: "secret", client: ReleaseNetHttpClient.new)
          first.create_request(operation)
          second.create_request(operation)
          keys = state["requests"].select { |item| item["path"] == "/payouts" }.map { |item| item.dig("headers", "idempotency-key")&.first }.compact
          expect(keys).to eq(["stable-key", "stable-key"])

          events = {
            "payout.processing" => "in_progress",
            "payout.completed" => "approved",
            "payout.failed" => "rejected",
            "payout.cancelled" => "rejected"
          }
          events.each do |event, canonical|
            body = JSON.generate("event" => event, "status" => event.split(".").last, "payout_id" => "np-1")
            signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "secret", body)
            result = first.process_callback(raw_body: body, signature: signature)
            expect(result).to include("ok" => true, "status" => canonical)
          end

          valid_body = JSON.generate("event" => "payout.completed", "status" => "completed", "payout_id" => "np-1")
          expect(first.process_callback(raw_body: valid_body, signature: "bad")).to include("ok" => false, "error_code" => "invalid_webhook_signature")
          expect(first.process_callback(raw_body: valid_body)).to include("ok" => false, "error_code" => "missing_webhook_signature")
          contradiction = JSON.generate("event" => "payout.completed", "status" => "failed", "payout_id" => "np-1")
          contradiction_signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "secret", contradiction)
          expect(first.process_callback(raw_body: contradiction, signature: contradiction_signature)).to include("ok" => false, "error_code" => "webhook_contradiction")
          unknown = JSON.generate("event" => "payout.unknown", "status" => "unknown")
          unknown_signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "secret", unknown)
          expect(first.process_callback(raw_body: unknown, signature: unknown_signature)).to include("ok" => false, "error_code" => "unknown_webhook_event")
          expect(first.process_callback(raw_body: "", signature: "bad")).to include("ok" => false, "error_code" => "missing_raw_body")
        end
      end
    end
  end

  it "executes the frozen scale-1000 generated case with an explicit provider profile input" do
    root = SpecSupport::ROOT
    Dir.mktmpdir("scale-1000") do |directory|
      defaults = File.join(directory, "millstone.yml")
      File.write(defaults, <<~YAML, encoding: "UTF-8")
        money:
          provider_subunit: mills
          scale: 1000
        statuses:
          processing: in_progress
          settled: approved
          declined: rejected
      YAML
      pipeline = pipeline_for(File.join(root, "research", "black_box_v1", "specs", "07_scale_1000.yaml"), File.join(root, "profiles", "space_payments_v1.yml"), defaults)
      expect(pipeline.blueprint.dig("money", "request_conversion", "factor")).to eq(1000)
      pipeline.validate_blueprint!
      blueprint = ProviderCompiler::Util.deep_dup(pipeline.blueprint)
      blueprint["servers"] = [{ "url" => "https://sandbox.millstone.example/v1", "environment" => "sandbox" }]
      start_provider do |base_url, _state|
        with_env("MILLSTONE_BASE_URL", base_url) do
          service_class = generated_service(pipeline, File.join(directory, "generated"), blueprint: blueprint)
          result = service_class.new(api_key: "mill-key", client: ReleaseNetHttpClient.new).create_request("amount" => 1.234, "recipient" => { "type" => "bank" })
          expect(result).to include("ok" => true, "http_status" => "200")
        end
      end
    end
  end
end
