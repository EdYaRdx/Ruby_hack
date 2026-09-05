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
      },
      "aurora_resolved" => {
        "label" => "Aurora (resolved)",
        "spec" => File.join(ROOT, "fixtures", "aurora_transfer_api.yaml"),
        "profile" => File.join(ROOT, "profiles", "aurora_payments_v1.yml"),
        "defaults" => File.join(ROOT, "fixtures", "aurora_case_defaults.yml"),
        "filename" => "aurora_transfer_api.yaml"
      },
      "heliospay" => {
        "label" => "HeliosPay",
        "spec" => File.join(ROOT, "fixtures", "heliospay_transfer_api.yaml"),
        "profile" => File.join(ROOT, "profiles", "heliospay_payments_v1.yml"),
        "defaults" => File.join(ROOT, "fixtures", "heliospay_case_defaults.yml"),
        "filename" => "heliospay_transfer_api.yaml"
      }
    }.freeze

    class Workspace
      attr_reader :id, :root_dir, :filename, :profile_path, :defaults_path, :pipeline, :generated_dir, :runtime_dir, :verification, :preview_results, :case_pack, :resolutions

      def initialize(id:, root_dir:, filename:, profile_path:, defaults_path:, case_pack: nil)
        @id = id
        @root_dir = root_dir
        @filename = filename
        @profile_path = profile_path
        @defaults_path = defaults_path
        @case_pack = case_pack
        @base_defaults_data = Util.deep_dup(CaseDefaults.load(defaults_path).data)
        @defaults_data = Util.deep_dup(@base_defaults_data)
        @resolutions = {}
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
        @pipeline = Pipeline.new(spec_path: spec_path, profile_path: profile_path, defaults_path: defaults_path, defaults_data: @defaults_data)
        @preview_results.clear
        @fixture_data = nil
        @verification = nil
        @generated = false
        @runtime_loaded = false
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
        blueprint && blueprint["decision"] == "ACCEPT" && unresolved_decisions.empty?
      end

      def blocking_decisions
        Array(blueprint && blueprint["decisions"]).select { |item| item["severity"] == "BLOCKING" }
      end

      def unresolved_decisions
        Array(blueprint && blueprint["decisions"]).select do |item|
          item["outcome"] == "REVIEW_REQUIRED" || item["outcome"] == "UNKNOWN" || item["severity"] == "BLOCKING"
        end
      end

      def resolve!(decision_id, params)
        override = resolution_override(decision_id.to_s, params)
        @resolutions[decision_id.to_s] = override
        @defaults_data = merge_defaults(@base_defaults_data, @resolutions.values)
        FileUtils.rm_rf(generated_dir) if File.directory?(generated_dir)
        FileUtils.rm_rf(runtime_dir) if File.directory?(runtime_dir)
        analyze!
      end

      def generate!
        raise Error, "generation is blocked until all critical decisions are resolved" unless accepted?

        pipeline.validate_blueprint!
        FileUtils.rm_rf(generated_dir) if File.exist?(generated_dir)
        DeterministicGenerator.new.generate(blueprint, manifest, generated_dir, examples: defaults.examples, spec_document: pipeline.source_document.resolved)
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

      def preview_fixtures
        fixture_data
      end

      def cleanup
        FileUtils.rm_rf(root_dir) if root_dir && File.directory?(root_dir)
      end

      private

      def resolution_override(decision_id, params)
        case decision_id
        when "money:amount-units"
          unit = params.fetch("provider_unit", "").to_s
          subunit = params.fetch("provider_subunit", "").to_s
          scale = Integer(params.fetch("scale", ""), 10)
          raise ValidationError, ["выберите единицу суммы провайдера и положительный scale"] unless %w[major minor].include?(unit) && !subunit.empty? && scale.positive?

          { "money" => { "provider_unit" => unit, "provider_subunit" => subunit, "scale" => scale, "source" => "HUMAN_CONFIRMED" } }
        when "status:provider-map"
          statuses = params.keys.filter_map do |key|
            match = key.match(/\Astatus_(\d+)_provider\z/)
            next unless match

            provider_value = params.fetch(key).to_s
            canonical = params.fetch("status_#{match[1]}_value", "").to_s
            next if provider_value.empty? || canonical.empty?

            [provider_value, canonical]
          end.to_h
          raise ValidationError, ["укажите канонический статус для каждого значения провайдера"] if statuses.empty? || statuses.values.any? { |value| !%w[in_progress approved rejected].include?(value) }

          { "statuses" => statuses, "status_source" => "HUMAN_CONFIRMED" }
        when "fields:create-request"
          mappings = params.keys.filter_map do |key|
            match = key.match(/\Afield_(\d+)_canonical\z/)
            next unless match

            index = match[1]
            canonical_path = params.fetch(key).to_s
            provider_path = params.fetch("field_#{index}_path", "").to_s
            next if canonical_path.empty? || provider_path.empty?

            direction = params.fetch("field_#{index}_direction", "request").to_s
            transform = params.fetch("field_#{index}_transform", "identity").to_s
            factor = Float(params.fetch("field_#{index}_factor", "1"), exception: false)
            raise ValidationError, ["выберите поддерживаемое преобразование поля и положительный factor"] unless %w[request response].include?(direction) && %w[identity money_to_provider provider_to_money status_map].include?(transform) && factor&.finite? && factor.positive?

            { "canonical_path" => canonical_path, "provider_path" => provider_path, "direction" => direction, "transform" => transform, "factor" => factor, "required" => params.fetch("field_#{index}_required", "false") == "true", "provenance" => "HUMAN_CONFIRMED", "decision" => "ACCEPT" }
          end
          raise ValidationError, ["укажите поле провайдера для каждого нерешённого сопоставления"] if mappings.empty?

          { "field_mappings" => mappings }
        when "webhook:signature"
          encoding = params.fetch("webhook_encoding", "").to_s
          raw_body = params.fetch("webhook_raw_body", "") == "true"
          raise ValidationError, ["выберите encoding webhook"] unless %w[hex base64].include?(encoding)

          { "webhook" => { "raw_body" => raw_body, "signature_encoding" => encoding, "source" => "HUMAN_CONFIRMED" } }
        when "idempotency:header"
          mode = params.fetch("idempotency_mode", "none").to_s
          raise ValidationError, ["выберите допустимое решение для idempotency header"] unless %w[none header].include?(mode)

          header = mode == "header" ? params.fetch("idempotency_header", "").to_s : nil
          raise ValidationError, ["укажите имя idempotency header"] if mode == "header" && header.empty?

          { "idempotency" => { "header" => header, "spec_required" => false, "source" => "HUMAN_CONFIRMED" } }
        else
          raise ValidationError, ["это решение нельзя подтвердить из Web UI без дополнительного case input"]
        end
      rescue ArgumentError
        raise ValidationError, ["scale должен быть положительным целым числом"]
      end

      def merge_defaults(base, overrides)
        result = Util.deep_dup(base)
        overrides.each do |override|
          override.each do |key, value|
            if key == "field_mappings"
              existing = Array(result["field_mappings"])
              Array(value).each do |mapping|
                existing.reject! { |item| item["canonical_path"] == mapping["canonical_path"] && item["direction"] == mapping["direction"] }
                existing << mapping
              end
              result[key] = existing
            elsif key == "statuses"
              result[key] = result.fetch(key, {}).merge(value)
            elsif result[key].is_a?(Hash) && value.is_a?(Hash)
              result[key] = result[key].merge(value)
            else
              result[key] = value
            end
          end
        end
        result
      end

      def ensure_runtime_service
        return if @runtime_loaded

        FileUtils.mkdir_p(runtime_dir)
        DeterministicGenerator.new.generate(blueprint, manifest, runtime_dir, examples: defaults.examples, spec_document: pipeline.source_document.resolved)
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
        operation = Util.deep_dup(fixture_data.dig("create_request", "operation") || {})
        operation["amount"] = params.fetch("amount", operation.fetch("amount", "1500.50"))
        operation["currency"] = params.fetch("currency", operation.fetch("currency", blueprint.dig("money", "host", "currency")))
        operation["external_id"] = params.fetch("external_id", operation.fetch("external_id", "preview-operation"))
        operation["idempotency_key"] ||= "preview-idempotency-key"
        recipient = operation["recipient"] = Util.deep_dup(operation.fetch("recipient", {}))
        recipient["type"] ||= params.fetch("recipient_type", "bank")
        recipient["kind"] ||= params.fetch("recipient_kind", recipient["type"])
        recipient["phone"] ||= params["recipient_phone"] if params["recipient_phone"]
        recipient["bank_code"] ||= params["recipient_bank_code"] if params["recipient_bank_code"]
        recipient["account"] ||= params["recipient_account"] if params["recipient_account"]
        recipient["routing_number"] ||= params["recipient_routing_number"] if params["recipient_routing_number"]
        recipient["card_number"] ||= params["recipient_card_number"] if params["recipient_card_number"]
        request = runtime_service.build_create_request(operation)
        {
          "host_input" => operation,
          "conversion" => blueprint.fetch("money").fetch("request_conversion"),
          "provider_request" => request
        }
      end

      def preview_response
        provider_body = Util.deep_dup(fixture_data.dig("fetch_status", "response") || {})
        provider_body = { "id" => "preview-provider-operation", "status" => "pending" } if provider_body.empty?
        amount_mapping = Array(blueprint["field_mappings"]).find { |mapping| mapping["canonical_path"] == "operation.amount" && mapping["direction"] == "response" }
        if amount_mapping
          conversion = blueprint.dig("money", "request_conversion") || {}
          host_amount = BigDecimal("1500.50")
          provider_amount = host_amount * BigDecimal((conversion["factor_decimal"] || conversion["factor"] || 1).to_s)
          provider_amount = provider_amount.frac.zero? ? provider_amount.to_i : provider_amount.to_f
          set_fixture_path(provider_body, amount_mapping["provider_path"].sub("response.", ""), provider_amount)
        end
        provider_id_mapping = Array(blueprint["field_mappings"]).find { |mapping| mapping["canonical_path"] == "operation.provider_operation_id" && mapping["direction"] == "response" }
        provider_id = provider_id_mapping && read_fixture_path(provider_body, provider_id_mapping["provider_path"].sub("response.", ""))
        provider_id ||= read_fixture_path(provider_body, "id") || "preview-provider-operation"
        success_status = Array(blueprint.dig("endpoints").find { |endpoint| endpoint["canonical"] == "fetch_status" }&.fetch("success_statuses", [])).first || "200"
        client = Object.new
        client.define_singleton_method(:request) { |_method, _url, _headers, _body, _query| { "http_status" => success_status.to_i, "body" => provider_body } }
        result = runtime_service(client: client).fetch_status("provider_operation_id" => provider_id)
        { "provider_response" => { "http_status" => success_status.to_i, "body" => provider_body }, "host_result" => result }
      end

      def preview_webhook
        callback = Util.deep_dup(fixture_data.dig("process_callback", "body") || {})
        callback = { "event" => blueprint.dig("webhook", "events")&.keys&.first || "preview.completed", "id" => "preview-provider-operation", "status" => "pending" } if callback.empty?
        body = JSON.generate(callback)
        secret = "demo-webhook-secret"
        signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), secret, body)
        result = runtime_service(webhook_secret: secret).process_callback(raw_body: body, signature: signature)
        { "event" => callback["event"], "signature_model" => blueprint.fetch("webhook").fetch("signature"), "result" => result }
      end

      def fixture_data
        @fixture_data ||= FixtureSynthesizer.new(blueprint, spec_document: pipeline.source_document.resolved, fallback_examples: defaults.examples).build
      end

      def read_fixture_path(object, path)
        path.to_s.split(".").reduce(object) { |current, key| current.is_a?(Hash) ? (current[key] || current[key.to_sym]) : nil }
      end

      def set_fixture_path(object, path, value)
        keys = path.to_s.split(".")
        leaf = keys.pop
        target = keys.reduce(object) { |current, key| current[key] ||= {} }
        target[leaf] = value
      end

      def ensure_runtime_base_service
        provider = if Object.const_defined?(:Provider, false)
                     Object.const_get(:Provider)
                   else
                     Object.const_set(:Provider, Module.new)
                   end
        return if provider.const_defined?(:BaseService, false)

        base_service = Class.new do
          def check_conditions(_operation, _request_method)
            success
          end

          def success(value = true)
            { "ok" => true, "value" => value }
          end

          def failure(status = nil, code = nil, message = nil)
            return { "ok" => false, "error" => status } if code.nil? && message.nil?

            { "ok" => false, "http_status" => status, "error" => message || code, "error_code" => code, "message" => message }
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

        create_workspace(
          filename: filename,
          content: content,
          profile_path: File.join(ROOT, "profiles", "space_payments_v1.yml"),
          defaults_path: File.join(ROOT, "fixtures", "empty_case_defaults.yml"),
          case_pack: nil
        )
      end

      def create_demo(name)
        config = DEMOS.fetch(name.to_s) { raise Error, "unknown demo" }
        content = File.binread(config.fetch("spec"))
        create_workspace(filename: config.fetch("filename"), content: content, profile_path: config.fetch("profile"), defaults_path: config.fetch("defaults"), case_pack: name.to_s)
      end

      def fetch(id)
        @workspaces.fetch(id.to_s) { raise Error, "workspace not found" }
      end

      def cleanup
        @workspaces.each_value(&:cleanup)
        @workspaces.clear
      end

      private

      def create_workspace(filename:, content:, profile_path:, defaults_path:, case_pack: nil)
        id = SecureRandom.hex(10)
        root_dir = Dir.mktmpdir("provider-compiler-web-")
        safe_name = File.basename(filename.to_s).gsub(/[^a-zA-Z0-9_.-]/, "_")
        extension = File.extname(safe_name).downcase
        target = File.join(root_dir, "provider_api#{extension}")
        File.binwrite(target, content)
        workspace = Workspace.new(id: id, root_dir: root_dir, filename: safe_name, profile_path: profile_path, defaults_path: defaults_path, case_pack: case_pack)
        @workspaces[id] = workspace
        workspace.analyze!
      rescue StandardError
        FileUtils.rm_rf(root_dir) if root_dir && File.directory?(root_dir)
        raise
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
          when "review"
            fields = form_fields(request)
            decision_id = fields.fetch("decision_id")
            workspace.resolve!(decision_id, fields)
            redirect(response, "/workspace/#{workspace.id}/review")
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
