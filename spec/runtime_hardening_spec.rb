# frozen_string_literal: true

require "json"
require "net/http"
require "webrick"

RSpec.describe "generated runtime hardening" do
  class BlackBoxHttpClient
    def request(method, url, headers, body, query)
      uri = URI.parse(url)
      query_pairs = URI.decode_www_form(uri.query.to_s) + Array(query).map { |key, value| [key.to_s, value.to_s] }
      uri.query = URI.encode_www_form(query_pairs) unless query_pairs.empty?
      request_class = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post }.fetch(method)
      request = request_class.new(uri)
      headers.each { |key, value| request[key] = value.to_s }
      request.body = JSON.generate(body) if body
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
      parsed_body = response.body.to_s.empty? ? nil : JSON.parse(response.body)
      { "http_status" => response.code.to_i, "headers" => response.each_header.to_h, "body" => parsed_body }
    end
  end

  class ObjectResponse
    attr_reader :status, :headers, :body

    def initialize(status, body, headers = {})
      @status = status
      @body = body
      @headers = headers
    end
  end

  class FallbackClient
    attr_reader :calls

    def initialize
      @calls = []
    end

    def post(url, headers, body)
      @calls << ["POST", url, headers, body]
      { "http_status" => 202, "body" => { "fund_id" => "hf-fallback-1", "phase" => "initiated", "settlement" => { "amount" => 1250 } } }
    end

    def get(url, headers)
      @calls << ["GET", url, headers]
      { "http_status" => 200, "body" => { "fund_id" => "hf-fallback-1", "phase" => "settled", "settlement" => { "amount" => 1250 } } }
    end
  end

  def start_fake_provider
    state = { "requests" => [] }
    server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
    server.mount_proc("/") do |request, response|
      body = request.body.to_s.empty? ? nil : JSON.parse(request.body)
      query = URI.decode_www_form(request.query_string.to_s).to_h
      state["requests"] << { "method" => request.request_method, "path" => request.path, "query" => query, "headers" => request.header, "body" => body }
      case [request.request_method, request.path]
      when ["POST", "/funds"]
        if body && body["client_reference"] == "bodyless"
          response.status = 204
          response.body = ""
        elsif body && body["client_reference"] == "rate-limited"
          response.status = 429
          response["Retry-After"] = "7"
          response["Content-Type"] = "application/json"
          response.body = JSON.generate("error" => { "message" => "slow down" })
        else
          response.status = 202
          response["Content-Type"] = "application/json"
          response.body = JSON.generate("fund_id" => "hf-local-1", "phase" => "initiated", "settlement" => { "amount" => 1250 })
        end
      when ["GET", "/funds/hf-local-1"]
        response.status = 200
        response["Content-Type"] = "application/json"
        response.body = JSON.generate("fund_id" => "hf-local-1", "phase" => "settled", "settlement" => { "amount" => 1250 })
      when ["POST", "/payouts"]
        reference = body && (body["reference"] || body["external_id"] || body["merchant_reference"])
        if reference == "rate-limited"
          response.status = 429
          response["Retry-After"] = "7"
          response["Content-Type"] = "application/json"
          response.body = JSON.generate("error" => { "message" => "slow down" })
        else
          response.status = 204
          response.body = ""
        end
      else
        response.status = 404
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

  def generate_service(pipeline, directory, blueprint: pipeline.blueprint)
    ProviderCompiler::DeterministicGenerator.new.generate(blueprint, pipeline.manifest, directory, examples: pipeline.defaults.examples)
    service_path = File.join(directory, "service.rb")
    service_name = "#{ProviderCompiler::Util.camel(pipeline.blueprint.dig("provider", "name"))}Service"
    Provider.send(:remove_const, service_name) if Provider.const_defined?(service_name, false)
    load service_path
    Provider.const_get(service_name)
  end

  def with_env(name, value)
    previous = ENV[name]
    ENV[name] = value
    yield
  ensure
    previous.nil? ? ENV.delete(name) : ENV[name] = previous
  end

  it "proves real localhost HTTP for query auth, JSON, create and status" do
    pipeline = ProviderCompiler::Pipeline.new(
      spec_path: File.join(SpecSupport::ROOT, "fixtures", "heliospay_transfer_api.yaml"),
      profile_path: File.join(SpecSupport::ROOT, "profiles", "heliospay_payments_v1.yml"),
      defaults_path: File.join(SpecSupport::ROOT, "fixtures", "heliospay_case_defaults.yml")
    )
    start_fake_provider do |base_url, state|
      with_env("HELIOSPAY_BASE_URL", base_url) do
        Dir.mktmpdir("runtime-http") do |directory|
          service_class = generate_service(pipeline, directory)
          service = service_class.new(api_key: "helios-key", client: BlackBoxHttpClient.new)
          operation = pipeline.defaults.examples.fetch("create_request").fetch("operation")

          created = service.create_request(operation)
          expect(created).to include("ok" => true, "http_status" => "202", "status" => "in_progress")
          expect(state["requests"].first.fetch("query")).to include("access_token" => "helios-key")
          expect(state["requests"].first.dig("body", "payment", "amount")).to eq(1250)

          fetched = service.fetch_status(provider_operation_id: "hf-local-1")
          expect(fetched).to include("ok" => true, "http_status" => "200", "status" => "approved")
          expect(state["requests"].last.fetch("path")).to eq("/funds/hf-local-1")
        end
      end
    end
  end

  it "proves header auth, bodyless 204 and Retry-After without selecting a missing error code" do
    pipeline = SpecSupport.pipeline
    start_fake_provider do |base_url, state|
      with_env("NOVAPAY_BASE_URL", base_url) do
        Dir.mktmpdir("runtime-http-novapay") do |directory|
          blueprint = Marshal.load(Marshal.dump(pipeline.blueprint))
          blueprint.fetch("endpoints").find { |item| item["canonical"] == "create_request" }.fetch("success_statuses") << "204"
          service_class = generate_service(pipeline, directory, blueprint: blueprint)
          service = service_class.new(api_key: "nova-key", client: BlackBoxHttpClient.new)
          operation = pipeline.defaults.examples.fetch("create_request").fetch("operation")

          result = service.create_request(operation.merge("id" => "bodyless"))
          expect(result).to include("ok" => false, "failure_code" => "internal_server_error", "i18n_key" => "provider.missing_provider_operation_id")
          expect(state["requests"].first.dig("headers", "x-api-key")).to eq(["nova-key"])

          limited = service.create_request(operation.merge("id" => "rate-limited"))
          expect(limited).to include("ok" => false, "http_status" => "429", "error_code" => nil, "retry_after" => "7")
          expect(limited.fetch("error_category")).to eq("rate_limit_exceeded")
        end
      end
    end
  end

  it "rejects contradictory webhook event and status after signature verification" do
    pipeline = SpecSupport.pipeline
    pipeline.validate_blueprint!
    Dir.mktmpdir("runtime-webhook") do |directory|
      service_class = generate_service(pipeline, directory)
      service = service_class.new(api_key: "nova-key", webhook_secret: "secret")
      body = JSON.generate("event" => "payout.completed", "status" => "failed", "payout_id" => "np-1")
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "secret", body)
      expect(service.process_callback(raw_body: body, signature: signature)).to include("ok" => false, "error_code" => "webhook_contradiction")
    end
  end

  it "passes query authentication through the get/post fallback interface" do
    pipeline = ProviderCompiler::Pipeline.new(
      spec_path: File.join(SpecSupport::ROOT, "fixtures", "heliospay_transfer_api.yaml"),
      profile_path: File.join(SpecSupport::ROOT, "profiles", "heliospay_payments_v1.yml"),
      defaults_path: File.join(SpecSupport::ROOT, "fixtures", "heliospay_case_defaults.yml")
    )
    Dir.mktmpdir("runtime-fallback") do |directory|
      service_class = generate_service(pipeline, directory)
      client = FallbackClient.new
      service = service_class.new(api_key: "fallback-key", client: client)
      service.create_request(pipeline.defaults.examples.fetch("create_request").fetch("operation"))
      service.fetch_status(provider_operation_id: "hf-fallback-1")
      expect(client.calls.map { |call| call[1] }).to all(include("access_token=fallback-key"))
    end
  end

  it "normalizes a response object instead of assuming a Hash transport" do
    pipeline = SpecSupport.pipeline
    Dir.mktmpdir("runtime-object-response") do |directory|
      service_class = generate_service(pipeline, directory)
      client = Class.new do
        def get(_url, _headers)
          ObjectResponse.new(200, { "status" => "completed", "amount" => 150_050 }, { "content-type" => "application/json" })
        end
      end.new
      result = service_class.new(api_key: "nova-key", client: client).fetch_status(id: "np-object-1")
      expect(result).to include("ok" => true, "http_status" => "200", "status" => "approved")
    end
  end

  it "uses the declared failure contract for runtime refusal paths" do
    pipeline = SpecSupport.pipeline
    pipeline.validate_blueprint!
    Dir.mktmpdir("runtime-failures") do |directory|
      service_class = generate_service(pipeline, directory)
      service = service_class.new(api_key: "nova-key", webhook_secret: "secret")
      expect(service.fetch_status({})).to include("ok" => false, "error_code" => "missing_provider_operation_id")
      expect(service.process_callback({})).to include("ok" => false, "error_code" => "missing_raw_body")

      body = JSON.generate("event" => "payout.unknown", "status" => "unknown")
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "secret", body)
      expect(service.process_callback(raw_body: body, signature: signature)).to include("ok" => false, "error_code" => "unknown_webhook_event")

      malformed_client = Class.new do
        def request(*); { "http_status" => 201, "body" => "not-json" }; end
      end.new
      malformed = service_class.new(api_key: "nova-key", client: malformed_client).create_request(pipeline.defaults.examples.fetch("create_request").fetch("operation"))
      expect(malformed).to include("ok" => false, "error_code" => "invalid_provider_response")

      unknown_status_client = Class.new do
        def request(*); { "http_status" => 201, "body" => { "id" => "np-unknown", "status" => "mystery" } }; end
      end.new
      unknown = service_class.new(api_key: "nova-key", client: unknown_status_client).create_request(pipeline.defaults.examples.fetch("create_request").fetch("operation"))
      expect(unknown).to include("ok" => false, "error" => "unknown provider status")
    end
  end
end
