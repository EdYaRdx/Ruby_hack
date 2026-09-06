# frozen_string_literal: true

module ProviderCompiler

  class AnalysisBundle
    attr_reader :sections, :decisions

    def initialize(sections, decisions)
      @sections = sections.freeze
      @decisions = decisions.freeze
      freeze
    end

    def decision_hashes
      decisions.map(&:to_h)
    end
  end

  class ReviewManifest
    attr_reader :data

    def initialize(source:, decisions:, blueprint_status:, override: nil)
      hashes = decisions.map(&:to_h)
      blocking = hashes.count { |item| item["severity"] == "BLOCKING" }
      review = hashes.count { |item| item["outcome"] == "REVIEW_REQUIRED" }
      @data = Immutable.deep_freeze(
        "schema_version" => 1,
        "source" => source,
        "blueprint_status" => blueprint_status,
        "review_override" => override ? { "status" => "APPLIED", "spec_fingerprint" => override.to_h["spec_fingerprint"], "decisions" => override.decisions.map { |item| item["decision_id"] } } : { "status" => "NONE" },
        "summary" => { "decisions" => hashes.length, "blocking" => blocking, "review_required" => review, "accepted" => hashes.count { |item| item["outcome"] == "ACCEPT" } },
        "decisions" => hashes
      )
      freeze
    end

    def to_h
      data
    end
  end

  class BlueprintBuilder
    def build(facts, profile, bundle)
      sections = bundle.sections
      operation_items = sections.fetch(:operations)
      canonical = operation_items.reject { |item| item["canonical"].nil? || item["canonical"] == "extra_operation" || item["canonical"] == "extra_unmapped" }
      extras = operation_items.select { |item| item["canonical"].nil? || %w[extra_operation extra_unmapped].include?(item["canonical"]) }.map do |item|
        { "operation_id" => item["operation_id"], "method" => item["method"], "path" => item["path"], "success_statuses" => Array(item["success_statuses"]), "kind" => "EXTRA_OPERATION", "preserved" => true, "blocking" => false, "canonical_binding" => "none_unless_profile_declares_#{item["operation_id"].to_s.sub(/\Aget/i, "").downcase}" }
      end
      all_decisions = bundle.decision_hashes
      overall = if all_decisions.any? { |item| item["outcome"] == "UNKNOWN" }
                  "UNKNOWN"
                elsif all_decisions.any? { |item| item["outcome"] == "REVIEW_REQUIRED" }
                  "REVIEW_REQUIRED"
                else
                  "ACCEPT"
                end
      provider_name = facts.info.fetch("title", "Provider").to_s.split.first
      endpoints = facts.operations.map do |operation|
        mapping = operation_items.find { |item| item["operation_id"] == operation["operation_id"] && item["path"] == operation["path"] }
        { "operation_id" => operation["operation_id"], "method" => operation["method"], "path" => operation["path"], "success_statuses" => Array(operation["success_statuses"]), "canonical" => mapping && mapping["canonical"], "decision" => mapping && mapping.dig("decision", "outcome") }
      end
      {
        "schema_version" => 1,
        "source" => facts.source.to_h,
        "provider" => { "name" => provider_name, "slug" => Util.slug(provider_name), "version" => facts.info["version"] },
        "servers" => facts.servers.map { |server| { "url" => server["url"], "environment" => server["description"].to_s.downcase.include?("sandbox") ? "sandbox" : "production" } },
        "base_service_profile" => { "name" => profile.name, "version" => profile.profile_version, "class_name" => profile.class_name, "required_methods" => profile.required_methods, "request_method_semantics" => profile.data["request_method_semantics"], "canonical_operations" => profile.canonical_operations, "money" => profile.money, "callback_actions" => profile.callback_actions, "check_conditions" => profile.check_conditions, "failure_contract" => profile.failure_contract, "host_operation" => profile.host_operation, "host_projection" => profile.host_projection, "request_method" => profile.request_method, "create_result" => profile.create_result },
        "auth" => sections.fetch(:auth),
        "operations" => canonical,
        "endpoints" => endpoints,
        "field_mappings" => sections.fetch(:field_mappings),
        "constraints" => sections.fetch(:constraints),
        "money" => sections.fetch(:money),
        "statuses" => sections.fetch(:statuses),
        "errors" => sections.fetch(:errors),
        "unsupported_features" => sections.fetch(:unsupported_features),
        "idempotency" => sections.fetch(:idempotency),
        "webhook" => sections.fetch(:webhook),
        "conditionals" => sections.fetch(:conditionals),
        "host_projection" => sections.fetch(:host_projection, {}),
        "extra_operations" => extras,
        "decisions" => all_decisions,
        "warnings" => all_decisions.select { |item| item["severity"] == "WARNING" },
        "unknowns" => all_decisions.select { |item| item["outcome"] == "UNKNOWN" },
        "decision" => overall
      }
    end

    private

  end

  class BlueprintValidator
    REQUIRED = %w[schema_version source provider servers base_service_profile auth operations endpoints field_mappings constraints money statuses errors unsupported_features idempotency webhook conditionals extra_operations decisions warnings unknowns].freeze

    def validate!(blueprint, profile)
      issues = REQUIRED.reject { |key| blueprint.key?(key) }.map { |key| "missing blueprint key #{key}" }
      issues << "schema_version must be 1" unless blueprint["schema_version"] == 1
      issues << "at least one endpoint is required" if Array(blueprint["endpoints"]).empty?
      host_unit = blueprint.dig("money", "host", "unit")
      provider_unit = blueprint.dig("money", "provider", "unit")
      money_scale = blueprint.dig("money", "provider", "scale")
      issues << "money host unit is unresolved" unless MoneyConversion::UNITS.include?(host_unit)
      issues << "money provider unit is unresolved" unless MoneyConversion::UNITS.include?(provider_unit)
      request_conversion = blueprint.dig("money", "request_conversion")
      response_conversion = blueprint.dig("money", "response_conversion")
      issues << "money scale is unresolved for distinct representations" if host_unit != provider_unit && !MoneyConversion.normalize_scale(money_scale)
      issues << "request amount conversion is unresolved" unless MoneyConversion.consistent?(request_conversion, host_unit, provider_unit, scale: money_scale)
      issues << "response amount conversion is not the inverse request conversion" unless response_conversion == MoneyConversion.inverse(request_conversion)
      issues << "money host evidence is missing or provider evidence is mixed into it" unless blueprint.dig("money", "host", "evidence_source") == "BASE_SERVICE_PROFILE" && Array(blueprint.dig("money", "host", "evidence")).any?
      provider_sources = Array(blueprint.dig("money", "provider", "evidence")).map { |item| item["source"] }
      issues << "money provider evidence is missing or mixed with host provenance" unless provider_sources.any? { |source| %w[SPEC_FACT SPEC_DESCRIPTION CASE_DEFAULT HUMAN_CONFIRMED].include?(source) } && !provider_sources.include?("BASE_SERVICE_PROFILE")
      issues << "generated profile methods are incomplete" unless Array(blueprint.dig("base_service_profile", "required_methods")).sort == profile.required_methods.sort
      issues << "blocking semantic decisions prevent generation" if Array(blueprint["decisions"]).any? { |item| item["severity"] == "BLOCKING" }
      auth_scheme = Array(blueprint.dig("auth", "schemes")).find { |scheme| scheme["name"] == blueprint.dig("auth", "selected") }
      strategy = auth_scheme && auth_scheme["strategy"]
      supported_auth = strategy && ((strategy["kind"] == "api_key" && %w[header query].include?(strategy["transport"])) || (strategy["kind"] == "bearer" && strategy["transport"] == "header"))
      issues << "authentication selection is unresolved or unsupported" unless supported_auth
      issues << "status mapping is incomplete" if Array(blueprint["statuses"]).empty? || Array(blueprint["statuses"]).any? { |item| item["canonical_value"] == "UNKNOWN" }
      issues << "webhook signature semantics are unresolved" unless blueprint.dig("webhook", "decision") == "ACCEPT"
      critical_ids = %w[auth:security-schemes money:amount-units status:provider-map fields:create-request constraints:create-request]
      critical_ids.each do |decision_id|
        decision = Array(blueprint["decisions"]).find { |item| item["decision_id"] == decision_id }
        issues << "critical decision #{decision_id} is not ACCEPT" unless decision && decision["outcome"] == "ACCEPT" && decision["severity"] == "INFO"
      end
      issues << "idempotency spec_required must be a boolean or explicit unknown" unless [true, false, nil].include?(blueprint.dig("idempotency", "spec_required"))
      issues << "idempotency adapter policy must remain separate from spec evidence" unless blueprint.dig("idempotency", "adapter_policy", "provenance") == "ADAPTER_POLICY"
      required_endpoints = %w[create_request fetch_status]
      required_endpoints << "process_callback" unless blueprint.dig("webhook", "mode") == "polling_only"
      issues << "canonical endpoint bindings are incomplete" unless required_endpoints.all? { |role| Array(blueprint["endpoints"]).any? { |item| item["canonical"] == role } }
      if blueprint.dig("webhook", "mode") != "polling_only"
        webhook_decision = Array(blueprint["decisions"]).find { |item| item["decision_id"] == "webhook:signature" }
        issues << "critical decision webhook:signature is not ACCEPT" unless webhook_decision && webhook_decision["outcome"] == "ACCEPT" && webhook_decision["severity"] == "INFO"
      end
      declared_helpers = Array(profile.data["helpers"])
      profile.callback_actions.each do |status, action|
        issues << "callback action #{action} for #{status} is not declared by BaseServiceProfile" if action && !declared_helpers.include?(action)
      end
      raise BlueprintValidationError, issues unless issues.empty?

      true
    end
  end

end
