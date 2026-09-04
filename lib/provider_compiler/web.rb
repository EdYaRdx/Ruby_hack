# frozen_string_literal: true

require "webrick"
require "tmpdir"
require "stringio"
require "securerandom"
require "zlib"
require "rubygems/package"
require_relative "../provider_compiler"
require_relative "web_renderer"

module ProviderCompiler
  module Web
    ROOT = File.expand_path("../..", __dir__).freeze
    MAX_UPLOAD_BYTES = 5 * 1024 * 1024
    ALLOWED_EXTENSIONS = %w[.yaml .yml .json].freeze
    ARTIFACTS = %w[service.rb INTEGRATION.md fixtures.json provider_blueprint.json review_manifest.json contract_smoke.rb].freeze

    DEMOS = {
      "novapay" => {
        "label" => "NovaPay",
        "spec" => File.join(ROOT, "fixtures", "novapay_provider_api.yaml"),
        "profile" => File.join(ROOT, "profiles", "space_payments_v1.yml"),
        "defaults" => File.join(ROOT, "fixtures", "novapay_case_defaults.yml"),
        "filename" => "provider_api.yaml"
      },
      "ambiguous" => {
        "label" => "Ambiguous",
        "spec" => File.join(ROOT, "fixtures", "ambiguous_money_provider_api.yaml"),
        "profile" => File.join(ROOT, "profiles", "space_payments_v1.yml"),
        "defaults" => File.join(ROOT, "fixtures", "empty_case_defaults.yml"),
        "filename" => "ambiguous_money.yaml"
      },
      "aurora" => {
        "label" => "Aurora",
        "spec" => File.join(ROOT, "fixtures", "aurora_transfer_api.yaml"),
        "profile" => File.join(ROOT, "profiles", "aurora_payments_v1.yml"),
        "defaults" => File.join(ROOT, "fixtures", "empty_case_defaults.yml"),
        "filename" => "aurora_transfer_api.yaml"
      }
    }.freeze

    class Workspace
      attr_reader :id, :root_dir, :filename, :profile_path, :defaults_path, :pipeline, :generated_dir, :runtime_dir, :verification, :preview_results

      def initialize(id:, root_dir:, filename:, profile_path:, defaults_path:)
        @id = id
        @root_dir = root_dir
        @filename = filename
        @profile_path = profile_path
        @defaults_path = defaults_path
        @generated_dir = File.join(root_dir, "generated")
        @runtime_dir = File.join(root_dir, "runtime")
        @preview_results = {}
        @generated = false
        @runtime_loaded = false
      end

      def spec_path
        File.join(root_dir, "provider_api#{File.extname(filename).downcase}")
      end

      def analyze!
        @pipeline = Pipeline.new(spec_path: spec_path, profile_path: profile_path, defaults_path: defaults_path)
        self
      end

      def analyzed?
        !@pipeline.nil?
      end

      def blueprint
        pipeline&.blueprint
      end

      def manifest
        pipeline&.manifest
      end

      def profile
        @profile ||= BaseServiceProfile.load(profile_path)
      end

      def defaults
        pipeline&.defaults
      end

      def accepted?
        blueprint && blueprint["decision"] == "ACCEPT"
      end

      def blocking_decisions
        Array(blueprint && blueprint["decisions"]).select { |item| item["severity"] == "BLOCKING" }
      end

      def unresolved_decisions
        Array(blueprint && blueprint["decisions"]).select do |item|
          item["outcome"] == "REVIEW_REQUIRED" || item["outcome"] == "UNKNOWN" || item["severity"] == "BLOCKING"
        end
      end

      def generate!
        raise Error, "generation is blocked until all critical decisions are resolved" unless accepted?

        pipeline.validate_blueprint!
        FileUtils.rm_rf(generated_dir) if File.exist?(generated_dir)
        DeterministicGenerator.new.generate(blueprint, manifest, generated_dir, examples: defaults.examples)
        @verification = Verification.new.verify(generated_dir)
        @generated = true
        self
      end

      def generated?
        @generated && File.file?(File.join(generated_dir, "service.rb"))
      end

      def artifact(name)
        raise Error, "unknown artifact" unless ARTIFACTS.include?(name)
        raise Error, "artifacts have not been generated" unless generated?

        File.read(File.join(generated_dir, name), encoding: "UTF-8")
      end

      def bundle
        raise Error, "artifacts have not been generated" unless generated?

        buffer = StringIO.new
        gzip = Zlib::GzipWriter.new(buffer)
        Gem::Package::TarWriter.new(gzip) do |tar|
          ARTIFACTS.each do |name|
            path = File.join(generated_dir, name)
            data = File.binread(path)
            tar.add_file_simple(name, 0o644, data.bytesize) { |file| file.write(data) }
          end
        end
        gzip.close
        buffer.string
      end

      def preview!(kind, params = {})
        raise Error, "preview is unavailable while Blueprint decision is #{blueprint && blueprint["decision"]}" unless accepted?

        result = case kind.to_s
                 when "request" then preview_request(params)
                 when "response" then preview_response
                 when "webhook" then preview_webhook
                 else raise Error, "unsupported preview kind"
                 end
        @preview_results[kind.to_s] = result
      end

      def cleanup
        FileUtils.rm_rf(root_dir) if root_dir && File.directory?(root_dir)
      end

      private

      def ensure_runtime_service
        return if @runtime_loaded

        FileUtils.mkdir_p(runtime_dir)
        DeterministicGenerator.new.generate(blueprint, manifest, runtime_dir, examples: defaults.examples)
        ensure_runtime_base_service
        class_name = "#{Util.camel(blueprint.dig("provider", "name"))}Service"
        provider = Object.const_get(:Provider)
        provider.send(:remove_const, class_name) if provider.const_defined?(class_name, false)
        load File.join(runtime_dir, "service.rb")
        @runtime_class = Provider.const_get(class_name)
        @runtime_loaded = true
      end

      def runtime_service(client: nil, webhook_secret: nil)
        ensure_runtime_service
        @runtime_class.new(api_key: "demo-api-key", webhook_secret: webhook_secret, client: client)
      end

      def preview_request(params)
        operation = {
          "amount" => params.fetch("amount", "1500.50"),
          "currency" => params.fetch("currency", blueprint.dig("money", "host", "currency")),
          "external_id" => params.fetch("external_id", "demo-001"),
          "idempotency_key" => "demo-idempotency-key",
          "recipient" => {
            "type" => params.fetch("recipient_type", "sbp"),
            "phone" => params.fetch("recipient_phone", "79001234567"),
            "bank_code" => params.fetch("recipient_bank_code", "044525225"),
            "card_number" => params.fetch("recipient_card_number", "")
          }
        }
        request = runtime_service.build_create_request(operation)
        {
          "host_input" => operation,
          "conversion" => blueprint.fetch("money").fetch("request_conversion"),
          "provider_request" => request
        }
      end

      def preview_response
        provider_body = { "id" => "np-demo-001", "status" => "completed", "amount" => 150_050, "currency" => "RUB" }
        client = Object.new
        client.define_singleton_method(:get) { |_url, _headers| { "status" => 200, "body" => provider_body } }
        result = runtime_service(client: client).fetch_status("provider_operation_id" => "np-demo-001")
        { "provider_response" => { "http_status" => 200, "body" => provider_body }, "host_result" => result }
      end

      def preview_webhook
        body = JSON.generate("event" => "payout.completed", "payout_id" => "np-demo-001", "external_id" => "demo-001", "status" => "completed")
        secret = "demo-webhook-secret"
        signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), secret, body)
        result = runtime_service(webhook_secret: secret).process_callback(raw_body: body, signature: signature)
        { "event" => "payout.completed", "signature_model" => blueprint.fetch("webhook").fetch("signature"), "result" => result }
      end

      def ensure_runtime_base_service
        provider = if Object.const_defined?(:Provider, false)
                     Object.const_get(:Provider)
                   else
                     Object.const_set(:Provider, Module.new)
                   end
        return if provider.const_defined?(:BaseService, false)

        base_service = Class.new do
          def success(value = true)
            { "ok" => true, "value" => value }
          end

          def failure(message)
            { "ok" => false, "error" => message }
          end

          def approve_operation(operation)
            { "ok" => true, "action" => "approve_operation", "operation" => operation }
          end

          def reject_operation(operation)
            { "ok" => true, "action" => "reject_operation", "operation" => operation }
          end
        end
        provider.const_set(:BaseService, base_service)
      end
    end

    class WorkspaceStore
      def initialize
        @workspaces = {}
      end

      def create_upload(filename:, content:)
        extension = File.extname(filename.to_s).downcase
        raise ValidationError, ["only YAML, YML and JSON uploads are supported"] unless ALLOWED_EXTENSIONS.include?(extension)
        raise ValidationError, ["uploaded specification is too large (limit: #{MAX_UPLOAD_BYTES} bytes)"] if content.to_s.bytesize > MAX_UPLOAD_BYTES

        config = official_novapay?(content) ? DEMOS.fetch("novapay") : {
          "profile" => File.join(ROOT, "profiles", "space_payments_v1.yml"),
          "defaults" => File.join(ROOT, "fixtures", "empty_case_defaults.yml")
        }
        create_workspace(filename: filename, content: content, profile_path: config.fetch("profile"), defaults_path: config.fetch("defaults"))
      end

      def create_demo(name)
        config = DEMOS.fetch(name.to_s) { raise Error, "unknown demo" }
        content = File.binread(config.fetch("spec"))
        create_workspace(filename: config.fetch("filename"), content: content, profile_path: config.fetch("profile"), defaults_path: config.fetch("defaults"))
      end

      def fetch(id)
        @workspaces.fetch(id.to_s) { raise Error, "workspace not found" }
      end

      def cleanup
        @workspaces.each_value(&:cleanup)
        @workspaces.clear
      end

      private

      def create_workspace(filename:, content:, profile_path:, defaults_path:)
        id = SecureRandom.hex(10)
        root_dir = Dir.mktmpdir("provider-compiler-web-")
        safe_name = File.basename(filename.to_s).gsub(/[^a-zA-Z0-9_.-]/, "_")
        extension = File.extname(safe_name).downcase
        target = File.join(root_dir, "provider_api#{extension}")
        File.binwrite(target, content)
        workspace = Workspace.new(id: id, root_dir: root_dir, filename: safe_name, profile_path: profile_path, defaults_path: defaults_path)
        @workspaces[id] = workspace
        workspace.analyze!
      rescue StandardError
        FileUtils.rm_rf(root_dir) if root_dir && File.directory?(root_dir)
        raise
      end

      def official_novapay?(content)
        expected = Digest::SHA256.file(File.join(ROOT, "fixtures", "novapay_provider_api.yaml")).hexdigest
        Digest::SHA256.hexdigest(content.to_s) == expected
      end
    end

    class Application
      attr_reader :store

      def initialize(store: WorkspaceStore.new)
        @store = store
      end

      def call(request, response)
        response["Cache-Control"] = "no-store"
        case [request.request_method, request.path]
        when ["GET", "/"]
          response.body = Renderer.new.upload_page
        when ["GET", "/health"]
          json(response, "ok" => true)
        when ["GET", "/static/app.css"]
          response["Content-Type"] = "text/css; charset=UTF-8"
          response.body = File.read(File.join(ROOT, "web", "public", "app.css"), encoding: "UTF-8")
        when ["GET", "/static/app.js"]
          response["Content-Type"] = "application/javascript; charset=UTF-8"
          response.body = File.read(File.join(ROOT, "web", "public", "app.js"), encoding: "UTF-8")
        when ["POST", "/analyze"]
          analyze(request, response)
        when ["POST", "/demo"]
          analyze_demo(request, response)
        else
          route_workspace(request, response)
        end
      rescue ValidationError, Error, BlueprintValidationError => e
        response.status = 422
        response.body = Renderer.new.error_page(e.message)
      rescue StandardError => e
        response.status = 500
        response.body = Renderer.new.error_page("Unexpected server error: #{e.message}")
      ensure
        response["Content-Type"] ||= "text/html; charset=UTF-8"
      end

      private

      def analyze(request, response)
        fields = form_fields(request)
        upload = fields["spec_file"]
        unless upload.is_a?(Hash) && upload["data"]
          raise ValidationError, ["choose an OpenAPI YAML, YML or JSON file"]
        end

        workspace = store.create_upload(filename: upload.fetch("filename", "provider_api.yaml"), content: upload.fetch("data"))
        redirect(response, "/workspace/#{workspace.id}/analysis")
      end

      def analyze_demo(request, response)
        fields = form_fields(request)
        workspace = store.create_demo(fields.fetch("demo", "novapay"))
        redirect(response, "/workspace/#{workspace.id}/analysis")
      end

      def route_workspace(request, response)
        match = request.path.match(%r{\A/workspace/([a-f0-9]+)/([^/]+)(?:/([^/]+))?\z})
        raise Error, "route not found" unless match

        workspace = store.fetch(match[1])
        action = match[2]
        tail = match[3]
        if request.request_method == "GET"
          case action
          when "analysis" then response.body = Renderer.new.analysis_page(workspace, request.query["decision"])
          when "review" then response.body = Renderer.new.review_page(workspace)
          when "preview" then response.body = Renderer.new.preview_page(workspace, request.query["kind"] || "request")
          when "generate" then response.body = Renderer.new.generate_page(workspace, request.query["artifact"])
          when "artifact" then download_artifact(workspace, request, response)
          when "bundle" then download_bundle(workspace, response)
          else raise Error, "route not found"
          end
        elsif request.request_method == "POST"
          case action
          when "preview"
            fields = form_fields(request)
            workspace.preview!(fields.fetch("kind", "request"), fields)
            redirect(response, "/workspace/#{workspace.id}/preview?kind=#{WEBrick::HTTPUtils.escape_form(fields.fetch("kind", "request"))}")
          when "generate"
            workspace.generate!
            redirect(response, "/workspace/#{workspace.id}/generate")
          else
            raise Error, "route not found"
          end
        else
          raise Error, "method not allowed"
        end
      end

      def download_artifact(workspace, request, response)
        name = request.query["name"].to_s
        content = workspace.artifact(name)
        response["Content-Type"] = name.end_with?(".json") ? "application/json; charset=UTF-8" : "text/plain; charset=UTF-8"
        if request.query["download"] == "1"
          response["Content-Disposition"] = %(attachment; filename="#{name}")
        end
        response.body = content
      end

      def download_bundle(workspace, response)
        response["Content-Type"] = "application/gzip"
        response["Content-Disposition"] = %(attachment; filename="#{Util.slug(workspace.blueprint.dig("provider", "name"))}-artifacts.tar.gz")
        response.body = workspace.bundle
      end

      def form_fields(request)
        return {} if request.body.to_s.empty?

        content_type = request.header.fetch("content-type", [""]).first.to_s
        if content_type.start_with?("multipart/form-data")
          parse_multipart(request.body.to_s, content_type)
        else
          WEBrick::HTTPUtils.parse_query(request.body.to_s).each_with_object({}) do |(key, value), result|
            result[key] = value.is_a?(Array) ? value.last : value
          end
        end
      end

      def parse_multipart(body, content_type)
        boundary_match = content_type.match(/boundary=(?:"([^"]+)"|([^;]+))/)
        raise ValidationError, ["invalid multipart upload"] unless boundary_match

        boundary = boundary_match[1] || boundary_match[2]
        fields = {}
        body.split("--#{boundary}").each do |part|
          part = part.sub(/\A\r\n/, "").sub(/\r\n\z/, "")
          next if part.empty? || part == "--"

          header, data = part.split("\r\n\r\n", 2)
          next unless header && data

          disposition = header.lines.find { |line| line.downcase.start_with?("content-disposition:") }.to_s
          name = disposition[/name="([^"]+)"/, 1]
          next unless name

          filename = disposition[/filename="([^"]*)"/, 1]
          if filename
            fields[name] = { "filename" => File.basename(filename), "data" => data }
          else
            fields[name] = data
          end
        end
        fields
      end

      def redirect(response, location)
        response.status = 303
        response["Location"] = location
        response.body = ""
      end

      def json(response, payload)
        response["Content-Type"] = "application/json; charset=UTF-8"
        response.body = JSON.generate(payload)
      end
    end

    class Server
      def self.start(host: "127.0.0.1", port: 4567)
        store = WorkspaceStore.new
        application = Application.new(store: store)
        server = WEBrick::HTTPServer.new(BindAddress: host, Port: port, MaxRequestBodySize: MAX_UPLOAD_BYTES + 256 * 1024, AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN))
        server.mount_proc("/") { |request, response| application.call(request, response) }
        trap("INT") { server.shutdown }
        trap("TERM") { server.shutdown }
        puts "Provider Compiler running on http://#{host}:#{port}"
        STDOUT.flush
        server.start
      ensure
        store&.cleanup
      end
    end
  end
end
