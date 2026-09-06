# frozen_string_literal: true

require "json"
require "net/http"
require "tmpdir"
require "uri"
require "webrick"

module ProviderCompiler
  # Executes a generated adapter against an ephemeral local HTTP provider.
  #
  # This is verification evidence, not a provider-specific mapping engine:
  # request paths, auth, response shapes and status values are all read from
  # the generated Blueprint and fixtures.
  class TransportVerification
    def self.verify_from_output(output_dir)
      blueprint_path = File.join(output_dir, "provider_blueprint.json")
      fixtures_path = File.join(output_dir, "fixtures.json")
      return not_run("generated Blueprint or fixtures are unavailable") unless File.file?(blueprint_path) && File.file?(fixtures_path)

      blueprint = JSON.parse(File.read(blueprint_path, encoding: "UTF-8"))
      fixtures = JSON.parse(File.read(fixtures_path, encoding: "UTF-8"))
      new(blueprint, fixtures).verify(output_dir)
    rescue JSON::ParserError
      failed("generated Blueprint or fixtures are not valid JSON")
    rescue StandardError => e
      failed("localhost HTTP verification could not start: #{e.class}")
    end

    def self.not_run(reason)
      {
        "status" => "NOT_RUN",
        "method" => "localhost_http_e2e",
        "outbound_http_supported" => nil,
        "base_url_runtime_configurable" => nil,
        "reason" => reason,
        "external_provider_call" => { "executed" => false, "reason" => "No real sandbox endpoint/credentials supplied" }
      }
    end

    def self.failed(reason)
      {
        "status" => "FAIL",
        "method" => "localhost_http_e2e",
        "outbound_http_supported" => true,
        "base_url_runtime_configurable" => true,
        "reason" => reason,
        "external_provider_call" => { "executed" => false, "reason" => "No real sandbox endpoint/credentials supplied" }
      }
    end

    def initialize(blueprint, fixtures)
      @blueprint = blueprint
      @fixtures = fixtures
    end

    def verify(output_dir)
      create_endpoint = endpoint("create_request")
      status_endpoint = endpoint("fetch_status")
      return self.class.failed("required create/status endpoint is unavailable") unless create_endpoint && status_endpoint

      operation = transport_operation
      return self.class.failed("create fixture does not contain a host operation") unless operation.is_a?(Hash)

      service_path = File.join(output_dir, "service.rb")
      return self.class.failed("generated service is unavailable") unless File.file?(service_path)

      create_response = response_body
      status_response = response_body
      provider = LocalProvider.new(
        create_method: create_endpoint.fetch("method"),
        create_path: create_endpoint.fetch("path"),
        create_status: first_status(create_endpoint),
        create_body: create_response,
        status_method: status_endpoint.fetch("method"),
        status_path_prefix: status_endpoint.fetch("path").split("{", 2).first,
        status_status: first_status(status_endpoint),
        status_body: status_response
      )
      provider.start

      env_name = "#{Util.slug(@blueprint.dig("provider", "name")).upcase}_BASE_URL"
      expected_request = nil
      created = nil
      fetched = nil
      status_path = nil
      with_env(env_name, provider.base_url) do
        service_class = load_service(service_path)
        service = service_class.new(api_key: "transport-verification-key", client: NetHttpClient.new)
        expected_request = service.build_create_request(operation)
        created = service.create_request(operation)
        provider_operation_id = read(created, "provider_operation_id") || "transport-provider-id"
        status_path = status_endpoint.fetch("path").sub(/\{[^}]+\}/, escape_path_segment(provider_operation_id))
        fetched = service.fetch_status("provider_operation_id" => provider_operation_id)
      end

      create_actual = provider.requests.find { |request| request["method"] == create_endpoint.fetch("method") }
      status_actual = provider.requests.find { |request| request["method"] == status_endpoint.fetch("method") }
      checks = []
      checks << check("create.method", create_endpoint.fetch("method"), create_actual && create_actual["method"])
      checks << check("create.path", create_endpoint.fetch("path"), create_actual && create_actual["path"])
      checks << check("create.query", expected_request.fetch("query", {}).keys.sort, create_actual ? create_actual.fetch("query", {}).keys.sort : [])
      checks << check("create.auth", true, auth_location_present?(create_actual))
      checks << check("create.body", expected_request.fetch("body", {}), create_actual && create_actual["body"])
      if expected_request.key?("body") && !expected_request["body"].nil?
        checks << check("create.content_type", "application/json", header_value(create_actual, "content-type"))
      end
      checks << check("status.method", status_endpoint.fetch("method"), status_actual && status_actual["method"])
      checks << check("status.path", status_path, status_actual && status_actual["path"])
      checks << check("status.auth", true, auth_location_present?(status_actual))
      checks << check("response.parsing", true, created.is_a?(Hash) && created["ok"] == true && fetched.is_a?(Hash) && fetched["ok"] == true)
      expected_status = status_value("approved") || status_value("in_progress")
      if expected_status
        expected_canonical_status = status_value("approved") == expected_status ? "approved" : "in_progress"
        checks << check("response.status_mapping", expected_canonical_status, fetched.is_a?(Hash) ? fetched["status"] : nil)
      end

      {
        "status" => checks.all? { |item| item["passed"] } ? "PASS" : "FAIL",
        "method" => "localhost_http_e2e",
        "outbound_http_supported" => true,
        "base_url_runtime_configurable" => true,
        "base_url_env" => env_name,
        "auth_location" => auth_location,
        "create_request" => { "passed" => checks_for(checks, "create.").all? { |item| item["passed"] } },
        "status_request" => { "passed" => checks_for(checks, "status.").all? { |item| item["passed"] } },
        "response_parsing" => { "passed" => checks_for(checks, "response.").all? { |item| item["passed"] }, "result_status" => fetched.is_a?(Hash) ? fetched["status"] : nil },
        "checks" => checks,
        "requests" => { "create" => redact_request(create_actual), "status" => redact_request(status_actual) },
        "external_provider_call" => { "executed" => false, "reason" => "No real sandbox endpoint/credentials supplied" }
      }
    ensure
      provider&.stop
      restore_service
    end

    private

    class NetHttpClient
      def request(method, url, headers, body, query)
        uri = URI.parse(url)
        pairs = URI.decode_www_form(uri.query.to_s) + Array(query).map { |key, value| [key.to_s, value.to_s] }
        uri.query = URI.encode_www_form(pairs) unless pairs.empty?
        request_class = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post }.fetch(method)
        request = request_class.new(uri)
        headers.each { |key, value| request[key] = value.to_s }
        if body
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(body)
        end
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 5
        response = http.start { |client| client.request(request) }
        parsed_body = response.body.to_s.empty? ? nil : JSON.parse(response.body)
        { "http_status" => response.code.to_i, "headers" => response.each_header.to_h, "body" => parsed_body }
      end
    end

    class LocalProvider
      attr_reader :requests

      def initialize(create_method:, create_path:, create_status:, create_body:, status_method:, status_path_prefix:, status_status:, status_body:)
        @create_method = create_method
        @create_path = create_path
        @create_status = create_status
        @create_body = create_body
        @status_method = status_method
        @status_path_prefix = status_path_prefix
        @status_status = status_status
        @status_body = status_body
        @requests = []
        @server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
        @server.mount_proc("/") do |request, response|
          body = request.body.to_s.empty? ? nil : JSON.parse(request.body)
          captured = {
            "method" => request.request_method,
            "path" => request.path,
            "query" => URI.decode_www_form(request.query_string.to_s).to_h,
            "headers" => request.header,
            "body" => body
          }
          @requests << captured
          if request.request_method == @create_method && request.path == @create_path
            respond(response, @create_status, @create_body)
          elsif request.request_method == @status_method && request.path.start_with?(@status_path_prefix)
            respond(response, @status_status, @status_body)
          else
            respond(response, 404, { "error" => { "message" => "not found" } })
          end
        end
      end

      def start
        @thread = Thread.new { @server.start }
        100.times { break if @server.status == :Running; sleep 0.01 }
        raise Error, "localhost HTTP provider did not start" unless @server.status == :Running
      end

      def base_url
        "http://127.0.0.1:#{@server.config[:Port]}"
      end

      def stop
        @server&.shutdown
        @thread&.join
      end

      private

      def respond(response, status, body)
        response.status = status
        return if body.nil?

        response["Content-Type"] = "application/json"
        response.body = JSON.generate(body)
      end
    end

    def endpoint(canonical)
      Array(@blueprint["endpoints"]).find { |item| item["canonical"] == canonical }
    end

    def transport_operation
      operation = @fixtures.dig("create_request", "operation")
      operation = operation.is_a?(Hash) ? Util.deep_dup(operation) : {}
      operation["amount"] ||= 1
      operation["currency"] ||= @blueprint.dig("money", "host", "currency") || "XXX"
      operation["external_id"] ||= "transport-operation"
      recipient = operation["recipient"] = Util.deep_dup(operation["recipient"] || {})
      recipient["type"] ||= "bank"
      operation
    end

    def first_status(endpoint)
      Array(endpoint["success_statuses"]).first.to_i
    end

    def response_body
      fixture = @fixtures.dig("fetch_status", "response")
      body = fixture.is_a?(Hash) ? Util.deep_dup(fixture) : {}
      calculated_provider_amount = provider_amount
      approved_status = status_value("approved") || status_value("in_progress") || "pending"
      Array(@blueprint["field_mappings"]).select { |item| item["direction"].to_s == "response" }.each do |mapping|
        path = mapping.fetch("provider_path").sub("response.", "")
        current_value = read_path(body, path)
        amount_requires_fixture_value = mapping.fetch("canonical_path") == "operation.amount" && !numeric?(current_value)
        next unless current_value.nil? || amount_requires_fixture_value

        value = case mapping.fetch("canonical_path")
                when "operation.provider_operation_id" then "transport-provider-id"
                when "operation.status" then approved_status
                when "operation.amount" then calculated_provider_amount
                else nil
                end
        set_path(body, path, value) unless value.nil?
      end
      body["id"] ||= "transport-provider-id" if body.empty?
      body["status"] ||= approved_status if body.empty?
      body
    end

    def provider_amount
      amount = read_path(@fixtures.dig("create_request", "operation"), "amount") || 1
      conversion = @blueprint.dig("money", "request_conversion") || {}
      return amount if conversion["direction"] == "same_unit"

      converted = BigDecimal(amount.to_s) * BigDecimal((conversion["factor_decimal"] || conversion["factor"] || 1).to_s)
      converted.frac.zero? ? converted.to_i : converted.to_f
    end

    def numeric?(value)
      return false if value.nil?

      BigDecimal(value.to_s).finite?
    rescue ArgumentError
      false
    end

    def status_value(canonical)
      Array(@blueprint["statuses"]).find { |item| item["canonical_value"] == canonical }&.fetch("provider_value", nil)
    end

    def auth_location
      strategy = @blueprint.dig("auth", "strategy") || {}
      strategy["transport"] == "query" ? "query" : "header"
    end

    def auth_location_present?(request)
      return false unless request

      strategy = @blueprint.dig("auth", "strategy") || {}
      name = strategy["name"].to_s
      if auth_location == "query"
        request.fetch("query", {}).any? { |key, value| key.to_s.casecmp?(name) && !value.to_s.empty? }
      else
        request.fetch("headers", {}).any? do |key, value|
          key.to_s.casecmp?(name) && Array(value).any? { |item| !item.to_s.empty? }
        end
      end
    end

    def header_value(request, name)
      return nil unless request

      pair = request.fetch("headers", {}).find { |key, _value| key.to_s.casecmp?(name) }
      Array(pair && pair.last).first
    end

    def check(name, expected, actual)
      { "name" => name, "passed" => expected == actual, "expected" => expected, "actual" => actual }
    end

    def checks_for(checks, prefix)
      checks.select { |item| item["name"].start_with?(prefix) }
    end

    def redact_request(request)
      return nil unless request

      {
        "method" => request["method"],
        "path" => request["path"],
        "query" => redact_query(request.fetch("query", {})),
        "headers" => redact_headers(request.fetch("headers", {})),
        "body" => request["body"]
      }
    end

    def redact_query(query)
      query.each_with_object({}) do |(key, value), result|
        result[key] = sensitive_name?(key) ? "[REDACTED]" : value
      end
    end

    def redact_headers(headers)
      headers.each_with_object({}) do |(key, value), result|
        result[key] = if key.to_s.casecmp?("host")
                        ["127.0.0.1:<PORT>"]
                      elsif sensitive_name?(key)
                        Array(value).map { "[REDACTED]" }
                      else
                        value
                      end
      end
    end

    def sensitive_name?(name)
      name.to_s.match?(/authorization|api[-_]?key|token|secret|signature|idempotency/i)
    end

    def load_service(path)
      provider = if Object.const_defined?(:Provider, false)
                   Object.const_get(:Provider)
                 else
                   Object.const_set(:Provider, Module.new)
                 end
      @provider_module = provider
      @base_service_created = false
      unless provider.const_defined?(:BaseService, false)
        provider.const_set(:BaseService, Class.new do
          def check_conditions(_operation, _request_method); success; end
          def success(value = true); { "ok" => true, "value" => value }; end
          def failure(status = nil, code = nil, message = nil); { "ok" => false, "http_status" => status, "error" => message || code, "error_code" => code }; end
        end)
        @base_service_created = true
      end
      @service_name = "#{Util.camel(@blueprint.dig("provider", "name"))}Service"
      @previous_service = provider.const_get(@service_name, false) if provider.const_defined?(@service_name, false)
      provider.send(:remove_const, @service_name) if @previous_service
      load path
      provider.const_get(@service_name)
    end

    def restore_service
      return unless @provider_module && @service_name

      @provider_module.send(:remove_const, @service_name) if @provider_module.const_defined?(@service_name, false)
      @provider_module.const_set(@service_name, @previous_service) if @previous_service
      @provider_module.send(:remove_const, :BaseService) if @base_service_created && @provider_module.const_defined?(:BaseService, false)
    end

    def with_env(name, value)
      previous = ENV[name]
      ENV[name] = value
      yield
    ensure
      previous.nil? ? ENV.delete(name) : ENV[name] = previous
    end

    def read(object, key)
      return nil unless object.is_a?(Hash)

      object[key] || object[key.to_s] || object[key.to_sym]
    end

    def read_path(object, path)
      path.to_s.split(".").reduce(object) { |current, key| read(current, key) }
    end

    def set_path(object, path, value)
      keys = path.to_s.split(".")
      leaf = keys.pop
      target = keys.reduce(object) { |current, key| current[key] ||= {} }
      target[leaf] = value
    end

    def escape_path_segment(value)
      value.to_s.gsub(/[^A-Za-z0-9._~-]/) { |character| "%%%02X" % character.ord }
    end
  end
end
