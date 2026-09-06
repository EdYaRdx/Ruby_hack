# frozen_string_literal: true

module ProviderCompiler
  class StaleOverrideError < ValidationError; end

  module ReviewDefaults
    module_function

    def merge(base, overrides)
      result = Util.deep_dup(base || {})
      Array(overrides).each do |override|
        override.each do |key, value|
          if key.to_s == "field_mappings"
            existing = Array(result["field_mappings"])
            Array(value).each do |mapping|
              existing.reject! { |item| item["canonical_path"] == mapping["canonical_path"] && item["direction"] == mapping["direction"] }
              existing << Util.deep_dup(mapping)
            end
            result["field_mappings"] = existing
          elsif key.to_s == "statuses"
            result["statuses"] = result.fetch("statuses", {}).merge(Util.deep_dup(value))
          elsif result[key].is_a?(Hash) && value.is_a?(Hash)
            result[key] = result[key].merge(Util.deep_dup(value))
          else
            result[key] = Util.deep_dup(value)
          end
        end
      end
      result
    end
  end

  class ReviewOverride
    SCHEMA_VERSION = 1
    REQUIRED_KEYS = %w[schema_version provider spec_fingerprint root_document_sha256 base_service_profile profile_version created_at decisions].freeze
    CREDENTIAL_KEY = /(?:api[_-]?key|secret|password|token|credential|private[_-]?key)/i

    attr_reader :data

    def self.load(path)
      content = File.read(path, encoding: "UTF-8")
      parsed = YAML.safe_load(content, aliases: false) || {}
      new(parsed, path: path)
    rescue Errno::ENOENT => e
      raise ValidationError, ["cannot read review override #{path}: #{e.message}"]
    rescue Psych::Exception => e
      raise ValidationError, ["cannot parse review override #{path}: #{e.message}"]
    end

    def initialize(data, path: nil)
      @data = Util.deep_dup(data)
      @path = path
      validate_shape!
      reject_credentials!
      Immutable.deep_freeze(@data)
      freeze
    end

    def decisions
      Array(data["decisions"])
    end

    def defaults_overrides
      decisions.map { |decision| decision.fetch("value") }
    end

    def validate_against!(source_document, profile, known_decision_ids: nil)
      if data.fetch("spec_fingerprint") != source_document.fingerprint || data.fetch("root_document_sha256").to_s.upcase != source_document.root_sha256.to_s.upcase
        raise StaleOverrideError, ["STALE_OVERRIDE: specification changed after this Review decision was confirmed"]
      end

      if data.fetch("base_service_profile") != profile.name || data.fetch("profile_version").to_s != profile.profile_version.to_s
        raise ValidationError, ["PROFILE_MISMATCH: review override targets #{data.fetch("base_service_profile")} profile v#{data.fetch("profile_version")}, current profile is #{profile.name} v#{profile.profile_version}"]
      end

      if known_decision_ids
        unknown = decisions.map { |item| item.fetch("decision_id") } - Array(known_decision_ids)
        raise ValidationError, ["UNKNOWN_DECISION_ID: #{unknown.join(", ")}"] unless unknown.empty?
      end
      self
    end

    def to_h
      data
    end

    private

    def validate_shape!
      missing = REQUIRED_KEYS.reject { |key| data.key?(key) }
      raise ValidationError, ["review override is missing required keys: #{missing.join(", ")}"] unless missing.empty?
      raise ValidationError, ["review override schema_version must be #{SCHEMA_VERSION}"] unless data["schema_version"] == SCHEMA_VERSION
      raise ValidationError, ["review override provider must be an object"] unless data["provider"].is_a?(Hash)
      raise ValidationError, ["review override decisions must be an array"] unless data["decisions"].is_a?(Array)

      data["decisions"].each_with_index do |decision, index|
        unless decision.is_a?(Hash) && decision["decision_id"] && decision["value"] && decision["provenance"] == "HUMAN_CONFIRMED"
          raise ValidationError, ["review override decision #{index} must contain decision_id, value and HUMAN_CONFIRMED provenance"]
        end
      end
    end

    def reject_credentials!
      if contains_credential_key?(data)
        raise ValidationError, ["review override contains credential-like data; secrets must never be persisted"]
      end
    end

    def contains_credential_key?(value)
      case value
      when Hash
        value.any? { |key, item| key.to_s.match?(CREDENTIAL_KEY) || contains_credential_key?(item) }
      when Array
        value.any? { |item| contains_credential_key?(item) }
      else
        false
      end
    end
  end

  class ReviewExporter
    def self.build(source_document:, profile:, provider_name:, resolutions:)
      decisions = Array(resolutions).filter_map do |item|
        decision_id, value = item
        next if value.nil?

        {
          "decision_id" => decision_id.to_s,
          "value" => Util.deep_dup(value),
          "provenance" => "HUMAN_CONFIRMED",
          "evidence_reference" => "review:#{decision_id}",
          "note" => "Explicitly confirmed by a human reviewer"
        }
      end
      ReviewOverride.new(
        {
          "schema_version" => ReviewOverride::SCHEMA_VERSION,
          "provider" => { "name" => provider_name.to_s },
          "spec_fingerprint" => source_document.fingerprint,
          "root_document_sha256" => source_document.root_sha256,
          "base_service_profile" => profile.name,
          "profile_version" => profile.profile_version,
          "created_at" => Time.now.utc.iso8601,
          "decisions" => decisions
        }
      )
    end

    def self.write(path, **kwargs)
      override = build(**kwargs)
      Util.write_text(path, YAML.dump(override.to_h))
      path
    end
  end

  class IntegrationReadiness
    def self.write(output_dir, report)
      FileUtils.mkdir_p(output_dir)
      Util.write_text(File.join(output_dir, "integration_readiness.json"), Util.pretty_json(report) + "\n")
      Util.write_text(File.join(output_dir, "INTEGRATION_READINESS.md"), to_markdown(report))
      [File.join(output_dir, "integration_readiness.json"), File.join(output_dir, "INTEGRATION_READINESS.md")]
    end

    def self.build(pipeline, verification: nil, generated: false, stale_override: nil)
      decisions = Array(pipeline.blueprint["decisions"])
      decision_provenance = decisions.map { |decision| provenance_sources(decision) }
      accepted = decisions.count { |item| item["outcome"] == "ACCEPT" }
      accepted_without_human = decisions.count { |item| item["outcome"] == "ACCEPT" && !human_confirmed?(item) }
      spec_evidence = decision_provenance.count { |sources| sources.any? { |source| source.start_with?("SPEC_") } }
      builtin_evidence = decision_provenance.count { |sources| sources.any? { |source| source == "BUILTIN_RULE" || source == "GENERIC_RULE" } }
      case_default_evidence = decision_provenance.count { |sources| sources.include?("CASE_DEFAULT") }
      human_confirmed = decisions.count { |item| human_confirmed?(item) }
      counts = {
        "total_semantic_decisions" => decisions.length,
        # Kept for consumers of the v1 readiness schema. This is an outcome
        # count, not a claim that all values came from the specification.
        "automatic_accept_count" => accepted_without_human,
        "accepted_decisions" => accepted,
        "accepted_without_human_confirmed" => accepted_without_human,
        "spec_evidence_decisions" => spec_evidence,
        "builtin_rule_evidence_decisions" => builtin_evidence,
        "case_default_decisions" => case_default_evidence,
        "review_count" => decisions.count { |item| item["outcome"] == "REVIEW_REQUIRED" },
        "unknown_count" => decisions.count { |item| item["outcome"] == "UNKNOWN" },
        "blocking_count" => decisions.count { |item| item["severity"] == "BLOCKING" },
        "human_decisions_supplied" => human_confirmed,
        "unsupported_critical_features" => Array(pipeline.blueprint["unsupported_features"]).count { |item| item["generation_impact"] == "BLOCKING" }
      }
      generated_ok = generated && verification && verification["passed"] == true
      ready = pipeline.blueprint["decision"] == "ACCEPT" && counts["blocking_count"].zero? && generated_ok
      {
        "schema_version" => 1,
        "provider" => pipeline.blueprint["provider"],
        "spec_fingerprint" => pipeline.source_document.fingerprint,
        "root_document_sha256" => pipeline.source_document.root_sha256,
        "host_profile" => pipeline.blueprint["base_service_profile"],
        "operations" => {
          "found" => Array(pipeline.facts.operations).length,
          "canonical" => Array(pipeline.blueprint["operations"]),
          "extra" => Array(pipeline.blueprint["extra_operations"])
        },
        "semantics" => {
          "auth" => pipeline.blueprint["auth"],
          "money" => pipeline.blueprint["money"],
          "statuses" => pipeline.blueprint["statuses"],
          "fields" => pipeline.blueprint["field_mappings"],
          "webhook" => webhook_semantics(pipeline.blueprint),
          "idempotency" => pipeline.blueprint["idempotency"],
          "errors" => pipeline.blueprint["errors"]
        },
        "decisions" => {
          "counts" => counts,
          # Backward-compatible aliases retained for existing consumers.
          "spec_derived" => spec_evidence,
          "human_confirmed" => human_confirmed,
          "case_defaults" => case_default_evidence,
          "builtin_rule_evidence" => builtin_evidence,
          "adapter_policy" => Array(pipeline.blueprint.dig("idempotency", "adapter_policy")).empty? ? 0 : 1
        },
        "generation_ready" => pipeline.blueprint["decision"] == "ACCEPT" && counts["blocking_count"].zero?,
        "generated" => generated,
        "verification" => verification || { "status" => "NOT_RUN" },
        "runtime_transport" => verification && verification["transport"] || { "status" => "NOT_RUN", "method" => "localhost_http_e2e", "external_provider_call" => { "executed" => false, "reason" => "No real sandbox endpoint/credentials supplied" } },
        "required_runtime_configuration" => runtime_configuration(pipeline.blueprint),
        "known_limitations" => known_limitations(pipeline),
        "stale_override" => stale_override,
        "ready" => ready
      }
    end

    def self.to_markdown(report)
      counts = report.fetch("decisions").fetch("counts")
      <<~MD
        # Integration Readiness

        ## Provider

        - Provider: `#{report.dig("provider", "name")}`
        - Spec fingerprint: `#{report.fetch("spec_fingerprint")}`
        - Host profile: `#{report.dig("host_profile", "name")} v#{report.dig("host_profile", "version")}`

        ## Semantic coverage

        - Operations found: #{report.dig("operations", "found")}
        - Canonical operations: #{Array(report.dig("operations", "canonical")).map { |item| item["canonical"] || item["operation_id"] }.join(", ")}
        - Extra operations preserved: #{Array(report.dig("operations", "extra")).length}
        - Auth: `#{report.dig("semantics", "auth", "selected") || "unresolved"}`
        - Money: `#{report.dig("semantics", "money", "host", "unit")} -> #{report.dig("semantics", "money", "provider", "unit")}`
        - Status mappings: #{Array(report.dig("semantics", "statuses")).length}
        - Field mappings: #{Array(report.dig("semantics", "fields")).length}
        - Webhook mode: `#{report.dig("semantics", "webhook", "mode")}`
        - Idempotency spec required: `#{report.dig("semantics", "idempotency", "spec_required")}`

        ## Human effort

        - Total semantic decisions: #{counts.fetch("total_semantic_decisions")}
        - Accepted in current Blueprint: #{counts.fetch("accepted_decisions")}
        - Accepted without HUMAN_CONFIRMED: #{counts.fetch("accepted_without_human_confirmed")}
        - Decisions with SPEC evidence: #{counts.fetch("spec_evidence_decisions")}
        - Decisions with BUILTIN/generic rule evidence: #{counts.fetch("builtin_rule_evidence_decisions")}
        - Decisions resolved using CASE_DEFAULT: #{counts.fetch("case_default_decisions")}
        - Questions requiring review: #{counts.fetch("review_count")}
        - Human decisions supplied: #{counts.fetch("human_decisions_supplied")}
        - Blocking unknowns: #{counts.fetch("blocking_count")}
        - Unsupported critical features: #{counts.fetch("unsupported_critical_features")}

        ## Generation

        - `generation_ready`: `#{report.fetch("generation_ready")}`
        - `generated`: `#{report.fetch("generated")}`
        - Verification: `#{report.dig("verification", "passed") == true ? "PASS" : report.dig("verification", "status") || "NOT_RUN"}`
        - Overall readiness: `#{report.fetch("ready") ? "READY" : "NOT_READY"}`

        ## Runtime transport

        - Outbound HTTP supported: `#{report.dig("runtime_transport", "outbound_http_supported") == true ? "YES" : "NOT_RUN"}`
        - Executable verification: `#{report.dig("runtime_transport", "method") || "localhost_http_e2e"}` / `#{report.dig("runtime_transport", "status") || "NOT_RUN"}`
        - Create request: `#{report.dig("runtime_transport", "create_request", "passed") == true ? "PASS" : "NOT_RUN"}`
        - Status request: `#{report.dig("runtime_transport", "status_request", "passed") == true ? "PASS" : "NOT_RUN"}`
        - External provider call: `#{report.dig("runtime_transport", "external_provider_call", "executed") == true ? "EXECUTED" : "NOT_EXECUTED"}`

        ## Required runtime configuration

        #{Array(report.fetch("required_runtime_configuration")).map { |item| "- #{item}" }.join("\n")}

        ## Known limitations

        #{Array(report.fetch("known_limitations")).map { |item| "- #{item}" }.join("\n")}
      MD
    end

    def self.human_confirmed?(decision)
      candidate = decision["candidate"]
      Array(decision["evidence"]).any? { |item| item["source"] == "HUMAN_CONFIRMED" } || (candidate.is_a?(Hash) && candidate["source"] == "HUMAN_CONFIRMED")
    end
    private_class_method :human_confirmed?

    def self.provenance_sources(value, result = [])
      case value
      when Hash
        value.each do |key, item|
          key = key.to_s
          if %w[source candidate_source provenance].include?(key)
            result << item.to_s unless item.nil? || item.to_s.empty?
          elsif key == "evidence_sources"
            Array(item).each { |source| result << source.to_s unless source.nil? || source.to_s.empty? }
          end
          provenance_sources(item, result)
        end
      when Array
        value.each { |item| provenance_sources(item, result) }
      end
      result.uniq
    end
    private_class_method :provenance_sources

    def self.webhook_semantics(blueprint)
      webhook = Util.deep_dup(blueprint["webhook"] || {})
      explicit_mode = webhook["mode"].to_s.strip
      webhook["mode"] = if !explicit_mode.empty?
                           explicit_mode
                         elsif webhook["endpoint"] || webhook["signature"].is_a?(Hash) || webhook["events"].is_a?(Hash)
                           "webhook"
                         else
                           "unresolved"
                         end
      webhook
    end
    private_class_method :webhook_semantics

    def self.runtime_configuration(blueprint)
      slug = Util.slug(blueprint.dig("provider", "name"))
      ["#{slug.upcase}_BASE_URL (optional sandbox default)", "provider API credential passed to generated service"]
    end
    private_class_method :runtime_configuration

    def self.known_limitations(pipeline)
      limitations = ["Production Provider::BaseService and its client/result classes are not included in this checkout"]
      limitations << "Unsupported features remain blocking until explicitly mapped" unless Array(pipeline.blueprint["unsupported_features"]).empty?
      limitations << "Webhook secret and API credentials are runtime configuration, never persisted in Review overrides"
      limitations
    end
    private_class_method :known_limitations
  end
end
