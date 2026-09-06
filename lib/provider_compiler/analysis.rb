# frozen_string_literal: true

module ProviderCompiler

  class OperationMapper
    def initialize(profile)
      @profile = profile
    end

    def analyze(facts)
      mapped = facts.operations.map do |operation|
        classification = classify(operation)
        role = classification.fetch(:role)
        explicit = !operation["operation_id"].to_s.empty?
        outcome = role == "extra_unmapped" ? "REVIEW_REQUIRED" : "ACCEPT"
        outcome = classification.fetch(:outcome, outcome)
        severity = classification.fetch(:severity, role == "extra_unmapped" ? "WARNING" : "INFO")
        decision = Decision.new(
          id: "operation:#{Util.slug(operation["operation_id"] || operation["method"] + operation["path"])}",
          outcome: outcome,
          severity: severity,
          candidate: role,
          evidence: [Evidence.new(
            source: "SPEC_FACT",
            locations: [operation_location(operation)],
            excerpt: [operation["operation_id"], operation["summary"]].compact.join(" — ")
          )],
          rationale: classification.fetch(:rationale, explicit ? "operationId/path/method provide a deterministic operation candidate" : "path/method provide a structural operation candidate")
        )
        if %w[create_request fetch_status process_callback].include?(role) && Array(operation["success_statuses"]).empty?
          decision = Decision.new(
            id: decision.to_h.fetch("decision_id"),
            outcome: "REVIEW_REQUIRED",
            severity: "WARNING",
            candidate: role,
            evidence: [Evidence.new(source: "SPEC_FACT", locations: [operation_location(operation) + "/responses"], excerpt: "no documented 2xx response status")],
            rationale: "mapped operation has no documented success HTTP response"
          )
        end
        {
          "canonical" => role == "extra_operation" || role == "extra_unmapped" ? nil : role,
          "operation_id" => operation["operation_id"],
          "method" => operation["method"],
          "path" => operation["path"],
          "success_statuses" => Array(operation["success_statuses"]),
          "decision" => decision.to_h
        }
      end
      AnalysisResult.new(section: mapped, decisions: mapped.map { |item| item["decision"] }.map { |item| DecisionProxy.new(item) })
    end

    private

    def classify(operation)
      operation_id = operation["operation_id"].to_s.downcase
      path = operation["path"].to_s.downcase
      method = operation["method"].to_s.upcase
      text = [operation["summary"], operation["description"], *Array(operation["tags"])].compact.join(" ").downcase
      op_domain = semantic_domain(operation_id)
      path_domain = semantic_domain(path)

      if method == "POST" && webhook_signal?(operation, operation_id, path, text)
        return { role: "process_callback", rationale: "webhook/callback evidence identifies a callback operation" } if @profile.canonical_operation?("callback")
      end
      if method == "GET" && status_signal?(operation, operation_id, path, text)
        return { role: "fetch_status", rationale: "status text/path/response evidence identifies a status read" } if @profile.canonical_operation?("status")
      end

      if operation_id.match?(/cancel/) || path.match?(/cancel/)
        return { role: "cancel" } if @profile.canonical_operation?("cancel")
        return { role: "extra_operation" }
      end
      if operation_id.match?(/void|abort|revoke/) || path.match?(/void|abort|revoke/)
        return { role: "extra_operation", rationale: "unbound action is preserved as an extra operation" }
      end

      if method == "POST" && (create_signal?(operation) || op_domain || path_domain)
        if path_domain == :transaction && op_domain == :transaction
          return { role: "extra_unmapped", outcome: "UNKNOWN", severity: "BLOCKING", rationale: "generic transaction identity is ambiguous without a payout-like lifecycle signal" }
        end
        if op_domain && path_domain && op_domain != path_domain
          return { role: "create_request", outcome: "REVIEW_REQUIRED", severity: "WARNING", rationale: "operation identity signals conflict across operationId and path" }
        end
        return { role: "create_request" } if @profile.canonical_operation?("create")
      end
      if operation_id.include?("balance") || path.include?("balance")
        return { role: "balance" } if @profile.canonical_operation?("balance")
        return { role: "extra_operation" }
      end

      { role: "extra_operation" }
    end

    def webhook_signal?(operation, operation_id, path, text)
      source_kind = operation["source_kind"].to_s
      signature = Array(operation["parameters"]).any? { |parameter| parameter["name"].to_s.downcase.include?("signature") }
      source_kind == "webhook" || operation_id.match?( /webhook|callback|notify|notification/) || path.match?(%r{webhook|callback|notification}) || text.match?(/webhook|callback|notification|signed request/) || signature
    end

    def status_signal?(operation, operation_id, path, text)
      response_status = operation["responses"].values.any? do |response|
        properties = response.dig("content", "application/json", "schema", "properties") || {}
        properties.keys.any? { |name| name.to_s.match?(/\A(?:status|state|phase)\z/i) }
      end
      operation_id.match?(/status|state/) || path.match?(/status|state/) || text.match?(/status|state/) || (method_get?(operation) && response_status)
    end

    def method_get?(operation)
      operation["method"].to_s.upcase == "GET"
    end

    def create_signal?(operation)
      operation_id = operation["operation_id"].to_s.downcase
      path = operation["path"].to_s.downcase
      schema = operation.dig("request_body", "content", "application/json", "schema") || {}
      properties = schema.fetch("properties", {})
      amount_like = properties.keys.any? { |name| name.to_s.match?(/amount|sum|total|value/) }
      recipient_like = properties.keys.any? { |name| name.to_s.match?(/recipient|destination|beneficiar|payee/) }
      response_like = operation["responses"].values.any? do |response|
        response.dig("content", "application/json", "schema", "properties")&.keys&.any? { |name| name.to_s.match?(/\Aid\z|status/) }
      end
      operation_id.match?(/create|initiat|submit|make/) || path.match?(/payout|transfer|withdraw/) || (amount_like && (recipient_like || response_like))
    end

    def semantic_domain(value)
      text = value.to_s.downcase
      return :payout if text.match?(/payout/)
      return :transfer if text.match?(/transfer/)
      return :withdrawal if text.match?(/withdraw/)
      return :transaction if text.match?(/transaction/)

      nil
    end

    def operation_location(operation)
      "#/paths/#{operation["path"].gsub("/", "~1")}/#{operation["method"].downcase}"
    end
  end

  class DecisionProxy
    def initialize(data)
      @data = data
    end

    def to_h
      @data
    end

    def blocking?
      @data["severity"] == "BLOCKING"
    end

    def review?
      @data["outcome"] == "REVIEW_REQUIRED"
    end
  end

  class AuthAnalyzer
    def analyze(facts)
      schemes = facts.security_schemes.map do |name, scheme|
        {
          "name" => name,
          "type" => scheme["type"],
          "in" => scheme["in"],
          "parameter_name" => scheme["name"],
          "scheme" => scheme["scheme"],
          "decision" => supported?(scheme) ? "ACCEPT" : "REVIEW_REQUIRED",
          "strategy" => strategy_for(scheme)
        }
      end
      outgoing = canonical_outgoing_operations(facts)
      operation_requirements = outgoing.map { |item| operation_auth_candidate(item, schemes) }
      supported_schemes = schemes.select { |scheme| scheme["decision"] == "ACCEPT" }
      unresolved = operation_requirements.any? { |item| item["status"] != "resolved" }
      strategies = operation_requirements.filter_map { |item| item["strategy"] }.uniq { |strategy| Util.canonicalize(strategy) }
      auth_modes = operation_requirements.select { |item| item["status"] == "resolved" }.map { |item| item["strategy"] || { "kind" => "public" } }.uniq { |mode| Util.canonicalize(mode) }
      mixed = auth_modes.length > 1
      selected = if operation_requirements.any? && !unresolved && !mixed
                   schemes.find { |scheme| scheme["decision"] == "ACCEPT" && Util.canonicalize(scheme["strategy"]) == Util.canonicalize(strategies.first) }
                 else
                   supported_schemes.first
                 end
      decision_outcome = if operation_requirements.any? && (unresolved || mixed)
                           supported_schemes.empty? && unresolved ? "UNKNOWN" : "REVIEW_REQUIRED"
                         else
                           selected ? "ACCEPT" : "UNKNOWN"
                         end
      decision_severity = decision_outcome == "ACCEPT" ? "INFO" : "BLOCKING"
      conflicts = if mixed
                    [{
                      "kind" => "outgoing_operation_auth",
                      "operations" => operation_requirements.map { |item| item.slice("canonical", "operation_id", "path", "strategy", "scheme_names") }
                    }]
                  elsif unresolved
                    operation_requirements.select { |item| item["status"] != "resolved" }.map do |item|
                      item.slice("canonical", "operation_id", "path", "security_source", "security", "resolution")
                    end
                  else
                    []
                  end
      rationale = if mixed
                   "canonical outgoing operations require materially different authentication strategies"
                 elsif unresolved
                   "canonical outgoing operation authentication could not be resolved confidently"
                 elsif selected
                   operation_requirements.any? ? "canonical outgoing operations resolve to one supported authentication strategy" : "an explicit supported security scheme is present"
                 else
                   "no supported explicit authentication scheme was found"
                 end
      decision = Decision.new(
        id: "auth:security-schemes",
        outcome: decision_outcome,
        severity: decision_severity,
        candidate: operation_requirements.any? && (mixed || unresolved) ? { "operations" => operation_requirements } : selected,
        evidence: auth_evidence(schemes, operation_requirements),
        rationale: rationale,
        conflicts: conflicts
      )
      AnalysisResult.new(section: { "schemes" => schemes, "selected" => selected && selected["name"], "strategy" => selected && selected["strategy"], "operation_requirements" => operation_requirements }, decisions: [decision])
    end

    private

    def auth_evidence(schemes, operation_requirements)
      evidence = [Evidence.new(
        source: "SPEC_FACT",
        locations: ["#/components/securitySchemes"],
        excerpt: schemes.map { |scheme| scheme["name"] }.join(", ")
      )]
      operation_requirements.each do |item|
        evidence << Evidence.new(
          source: "SPEC_FACT",
          locations: [item.fetch("operation_location")],
          excerpt: "#{item["canonical"]} security (#{item["security_source"]}): #{item["scheme_names"].join(", ")}"
        )
      end
      evidence
    end

    def operation_auth_candidate(item, schemes)
      operation = item.fetch("operation")
      security, source = security_for(operation)
      resolution = resolve_security(security, schemes)
      {
        "canonical" => item.fetch("canonical"),
        "operation_id" => operation["operation_id"],
        "path" => operation["path"],
        "operation_location" => operation_location(operation),
        "security_source" => source,
        "security" => security,
        "status" => resolution.fetch("status"),
        "strategy" => resolution["strategy"],
        "auth_mode" => resolution["strategy"] || { "kind" => "public" },
        "scheme_names" => resolution.fetch("scheme_names"),
        "resolution" => resolution["resolution"]
      }
    end

    def security_for(operation)
      if operation["security_declared"]
        [operation["security"], "operation"]
      elsif operation["root_security_declared"]
        [operation["root_security"], "root"]
      else
        [nil, "provider_default"]
      end
    end

    def resolve_security(security, schemes)
      if security == []
        return { "status" => "resolved", "strategy" => nil, "scheme_names" => [], "resolution" => "explicitly_public" }
      end

      if security.nil?
        supported = schemes.select { |scheme| scheme["decision"] == "ACCEPT" }
        return { "status" => "resolved", "strategy" => supported.first["strategy"], "scheme_names" => [supported.first["name"]], "resolution" => "single_provider_strategy" } if supported.length == 1

        return { "status" => "unresolved", "strategy" => nil, "scheme_names" => [], "resolution" => supported.empty? ? "no_supported_scheme" : "multiple_provider_strategies_without_operation_requirement" }
      end

      return { "status" => "unresolved", "strategy" => nil, "scheme_names" => [], "resolution" => "security_requirement_is_not_an_array" } unless security.is_a?(Array) && !security.empty?

      alternatives = security.filter_map do |requirement|
        next unless requirement.is_a?(Hash) && requirement.length == 1

        name = requirement.keys.first.to_s
        scheme = schemes.find { |candidate| candidate["name"].to_s == name }
        next unless scheme && scheme["decision"] == "ACCEPT"

        { "name" => name, "strategy" => scheme["strategy"] }
      end
      return { "status" => "unresolved", "strategy" => nil, "scheme_names" => [], "resolution" => "unsupported_or_composite_security_requirement" } unless alternatives.length == security.length

      strategies = alternatives.map { |item| item["strategy"] }.uniq { |strategy| Util.canonicalize(strategy) }
      return { "status" => "unresolved", "strategy" => nil, "scheme_names" => alternatives.map { |item| item["name"] }, "resolution" => "alternative_strategies_differ" } unless strategies.length == 1

      { "status" => "resolved", "strategy" => strategies.first, "scheme_names" => alternatives.map { |item| item["name"] }, "resolution" => "operation_requirement" }
    end

    def canonical_outgoing_operations(facts)
      facts.operations.filter_map do |operation_fact|
        operation = operation_fact.to_h
        next if incoming_operation?(operation)

        role = if create_operation?(operation)
                 "create_request"
               elsif status_operation?(operation)
                 "fetch_status"
               end
        role ? { "canonical" => role, "operation" => operation } : nil
      end
    end

    def incoming_operation?(operation)
      return true if operation["source_kind"].to_s == "webhook"

      [operation["operation_id"], operation["path"], operation["summary"], operation["description"]].compact.join(" ").downcase.match?(/webhook|callback|notification/)
    end

    def create_operation?(operation)
      return false unless operation["method"].to_s.upcase == "POST"
      return false if operation["operation_id"].to_s.downcase.match?(/cancel|void|abort|revoke/)

      text = [operation["operation_id"], operation["path"], operation["summary"], operation["description"]].compact.join(" ").downcase
      return true if text.match?(/create|initiat|submit|payment|payout|transfer|withdraw|fund/)

      schema = operation.dig("request_body", "content", "application/json", "schema") || {}
      properties = schema.fetch("properties", {})
      properties.keys.any? { |name| name.to_s.match?(/amount|sum|total|value/) }
    end

    def status_operation?(operation)
      return false unless operation["method"].to_s.upcase == "GET"

      text = [operation["operation_id"], operation["path"], operation["summary"], operation["description"]].compact.join(" ").downcase
      return true if text.match?(/status|state/)

      operation.fetch("responses", {}).values.any? do |response|
        properties = response.dig("content", "application/json", "schema", "properties") || {}
        properties.keys.any? { |name| name.to_s.match?(/\A(?:status|state|phase)\z/i) }
      end
    end

    def operation_location(operation)
      "#/paths/#{operation["path"].to_s.gsub("/", "~1")}/#{operation["method"].to_s.downcase}"
    end

    def supported?(scheme)
      (scheme["type"] == "apiKey" && %w[header query].include?(scheme["in"])) || scheme["type"] == "http" && scheme["scheme"].to_s.downcase == "bearer"
    end

    def strategy_for(scheme)
      return nil unless supported?(scheme)

      if scheme["type"] == "apiKey"
        { "kind" => "api_key", "transport" => scheme["in"], "name" => scheme["name"] }
      else
        { "kind" => "bearer", "transport" => "header", "name" => "Authorization", "scheme" => "Bearer" }
      end
    end
  end

  module MoneyConversion
    module_function

    UNITS = %w[major minor].freeze

    def resolve(host_unit, provider_unit, scale: nil)
      return unresolved unless UNITS.include?(host_unit) && UNITS.include?(provider_unit)

      if host_unit == provider_unit
        { "status" => "resolved", "direction" => "same_unit", "operation" => "identity", "factor" => 1, "factor_decimal" => "1", "scale" => 1 }
      elsif normalize_scale(scale)
        normalized_scale = normalize_scale(scale)
        if host_unit == "major" && provider_unit == "minor"
          { "status" => "resolved", "direction" => "major_to_minor", "operation" => "multiply", "factor" => normalized_scale, "factor_decimal" => normalized_scale.to_s, "scale" => normalized_scale }
        else
          decimal_factor = BigDecimal(1) / BigDecimal(normalized_scale.to_s)
          { "status" => "resolved", "direction" => "minor_to_major", "operation" => "divide", "factor" => decimal_factor.to_f, "factor_decimal" => decimal_factor.to_s("F"), "scale" => normalized_scale }
        end
      else
        unresolved
      end
    end

    def inverse(conversion)
      return unresolved unless conversion && conversion["status"] == "resolved"
      return conversion.dup if conversion["direction"] == "same_unit"

      scale = normalize_scale(conversion["scale"])
      return unresolved unless scale

      if conversion["direction"] == "major_to_minor"
        decimal_factor = BigDecimal(1) / BigDecimal(scale.to_s)
        { "status" => "resolved", "direction" => "minor_to_major", "operation" => "divide", "factor" => decimal_factor.to_f, "factor_decimal" => decimal_factor.to_s("F"), "scale" => scale }
      elsif conversion["direction"] == "minor_to_major"
        { "status" => "resolved", "direction" => "major_to_minor", "operation" => "multiply", "factor" => scale, "factor_decimal" => scale.to_s, "scale" => scale }
      else
        unresolved
      end
    end

    def consistent?(conversion, host_unit, provider_unit, scale: nil)
      expected = resolve(host_unit, provider_unit, scale: scale)
      return false unless expected["status"] == "resolved" && conversion && conversion["status"] == "resolved"

      %w[status direction operation factor factor_decimal scale].all? { |key| conversion[key] == expected[key] }
    end

    def unresolved
      { "status" => "unresolved", "direction" => "unknown", "operation" => "unresolved", "factor" => nil, "factor_decimal" => nil, "scale" => nil }
    end

    def normalize_scale(value)
      return nil if value.nil?

      decimal = BigDecimal(value.to_s)
      return nil unless decimal.finite? && decimal > 0 && decimal.frac.zero?

      decimal.to_i
    rescue ArgumentError
      nil
    end
  end

  class MoneyAnalyzer
    def initialize(profile, defaults)
      @profile = profile
      @defaults = defaults
    end

    def analyze(facts)
      operation = facts.operations.find { |item| create_operation?(item) }
      schema = operation && operation.dig("request_body", "content", "application/json", "schema")
      schema ||= first_schema_with_property(facts.components, "amount") || {}
      properties = schema.fetch("properties", {})
      nested_money_name, nested_money_node = properties.find do |_name, node|
        node.is_a?(Hash) && node["properties"].is_a?(Hash) && node["properties"].keys.any? { |name| name.to_s.match?(/\A(?:value|amount)\z/i) }
      end
      nested_value_name = nested_money_node && nested_money_node.fetch("properties", {}).keys.find { |name| name.to_s.match?(/\A(?:value|amount)\z/i) }
      nested_value = nested_money_node && nested_value_name && nested_money_node.dig("properties", nested_value_name)
      nested_description = nested_money_node.is_a?(Hash) ? [nested_money_node["description"], nested_value && nested_value["description"]].compact.join(" ") : ""
      amount = properties["amount"] || (nested_value || {})
      amount_candidates = properties.keys.select { |name| name.to_s.match?(/amount|sum|total/) }
      # A nested value is not enough by itself to establish ownership of the
      # canonical amount. Require semantic evidence on the container (or an
      # explicit scale extension on the value). This keeps a mechanically
      # nested `money.value` mutation in review while accepting providers that
      # document the money object itself, such as Aurora and HeliosPay.
      nested_money = nested_value && (
        nested_money_node["description"].to_s.match?(/amount|money|sum|total|major|minor|currency|unit|cent|kopeck/i) ||
        nested_value.key?("x-minor-unit-scale") || nested_value.key?("minor_unit_scale") || nested_value.key?("minor_unit_exponent")
      )
      description = properties.key?("amount") ? amount["description"].to_s : nested_description
      described_unit = unit_from_description(description)
      default_unit = @defaults.money["provider_unit"] || unit_from_subunit(@defaults.money["provider_subunit"])
      structurally_resolved = properties.key?("amount") || nested_money
      provider_unit = structurally_resolved ? (described_unit || default_unit || "UNKNOWN") : "UNKNOWN"
      provider_subunit = @defaults.money["provider_subunit"] || subunit_from_description(description) || (provider_unit == "minor" ? "minor_unit" : "UNKNOWN")
      host_unit = @profile.canonical_amount["unit"] || "UNKNOWN"
      host_currency = @profile.canonical_amount["currency"] || "UNKNOWN"
      scale, scale_source = structurally_resolved ? resolve_scale(amount) : [nil, "UNKNOWN"]
      scale ||= 1 if provider_unit == host_unit
      currency_property = properties["currency"] || (nested_money_node.is_a?(Hash) ? nested_money_node.dig("properties", "currency") : nil) || {}
      provider_currency = Array(currency_property["enum"]).first || "UNKNOWN"
      provider_evidence = []
      escaped_path = operation && operation["path"].to_s.gsub("~", "~0").gsub("/", "~1")
      amount_location = if operation
                          field_pointer = properties.key?("amount") ? "amount" : [nested_money_name, nested_value_name].compact.join("/")
                          "#/paths/#{escaped_path}/#{operation["method"].to_s.downcase}/requestBody/content/application~1json/schema/properties/#{field_pointer.gsub("/", "~1")}/description"
                        else
                          "#/components/schemas/*/properties/amount/description"
                        end
      provider_evidence << Evidence.new(source: "SPEC_DESCRIPTION", locations: [amount_location], excerpt: description) if described_unit
      provider_evidence << Evidence.new(source: @defaults.money.fetch("source", "CASE_DEFAULT"), locations: ["organizer_case_qa.money"], excerpt: "provider amount unit and subunit") unless @defaults.money.empty?
      host_evidence = Evidence.new(source: "BASE_SERVICE_PROFILE", locations: ["profile#/canonical_amount"], excerpt: "operation.amount is #{host_unit} #{host_currency}")
      request_conversion = MoneyConversion.resolve(host_unit, provider_unit, scale: scale)
      response_conversion = MoneyConversion.inverse(request_conversion)
      conflict = described_unit && default_unit && described_unit != default_unit
      if conflict
        # A conflicting provider-unit signal must not leave a usable conversion
        # candidate in the Blueprint. The decision is blocking, so generation
        # must see the same unresolved state as the evidence ledger.
        request_conversion = MoneyConversion.unresolved
        response_conversion = MoneyConversion.unresolved
      end
      resolved = structurally_resolved && request_conversion["status"] == "resolved" && response_conversion["status"] == "resolved" && !conflict
      outcome = resolved ? "ACCEPT" : "REVIEW_REQUIRED"
      severity = resolved ? "INFO" : "BLOCKING"
      decision = Decision.new(
        id: "money:amount-units",
        outcome: outcome,
        severity: severity,
        candidate: { "host_unit" => host_unit, "provider_unit" => provider_unit, "request_conversion" => request_conversion },
        evidence: [host_evidence, *provider_evidence],
          rationale: conflict ? "spec description and case default disagree on provider amount unit" : (!structurally_resolved ? "the request schema does not expose a direct amount field" : (resolved ? "host and provider amount units are explicit and directional conversion is deterministic" : "both host and provider amount units are required before conversion")),
        conflicts: conflict ? [{ "sources" => ["SPEC_DESCRIPTION", "CASE_DEFAULT"], "field" => "provider.amount.unit" }] : []
      )
      section = {
        "host" => { "field" => "operation.amount", "currency" => host_currency, "unit" => host_unit, "representation" => host_unit, "source" => host_evidence.to_h["source"], "evidence_source" => host_evidence.to_h["source"], "evidence" => [host_evidence.to_h] },
        "provider" => { "field" => properties.key?("amount") ? "request.amount" : "request.#{nested_money_name}.#{nested_value_name}", "response_field" => response_money_field(facts), "currency" => provider_currency, "unit" => provider_unit, "representation" => provider_unit, "subunit" => provider_subunit, "unit_name" => provider_subunit, "scale" => scale, "scale_source" => scale_source, "source" => provider_evidence.map { |item| item.to_h["source"] }.uniq, "evidence_sources" => provider_evidence.map { |item| item.to_h["source"] }.uniq, "evidence" => provider_evidence.map(&:to_h), "field_candidates" => amount_candidates, "nested_money_candidate" => !nested_money.nil? },
        "request_conversion" => request_conversion,
        "response_conversion" => response_conversion,
        "decision" => outcome
      }
      AnalysisResult.new(section: section, decisions: [decision])
    end

    private

    def create_operation?(operation)
      return false unless operation["method"] == "POST"

      operation_id = operation["operation_id"].to_s
      schema = operation.dig("request_body", "content", "application/json", "schema") || {}
      properties = schema.fetch("properties", {})
      operation_id.match?(/create|initiat|submit/i) || properties.keys.any? { |name| name.to_s.match?(/amount|sum|total/) }
    end

    def response_money_field(facts)
      operation = facts.operations.find { |item| item["method"] == "GET" && item["responses"].values.any? { |response| response.dig("content", "application/json", "schema") } }
      schema = operation && operation["responses"].values.map { |response| response.dig("content", "application/json", "schema") }.compact.first
      path = find_money_path(schema)
      path ? "response.#{path}" : "response.amount"
    end

    def resolve_scale(amount)
      candidates = [
        [amount["minor_unit_scale"], "SPEC_FACT"],
        [amount["x-minor-unit-scale"], "SPEC_FACT"],
        [scale_from_exponent(amount["minor_unit_exponent"]), "SPEC_FACT"],
        [@profile.canonical_amount["scale"], "BASE_SERVICE_PROFILE"],
        [scale_from_exponent(@profile.canonical_amount["minor_unit_exponent"]), "BASE_SERVICE_PROFILE"],
        [@profile.money["scale"], "BASE_SERVICE_PROFILE"],
        [scale_from_exponent(@profile.money["minor_unit_exponent"]), "BASE_SERVICE_PROFILE"],
        [@defaults.money["scale"], "CASE_DEFAULT"],
        [@defaults.money["minor_unit_scale"], "CASE_DEFAULT"],
        [scale_from_exponent(@defaults.money["minor_unit_exponent"]), "CASE_DEFAULT"]
      ]
      candidates.find { |value, _source| MoneyConversion.normalize_scale(value) }.then do |value, source|
        value ? [MoneyConversion.normalize_scale(value), source] : [nil, "UNKNOWN"]
      end
    end

    def scale_from_exponent(value)
      return nil if value.nil?

      exponent = Integer(value)
      return nil unless exponent >= 0 && exponent <= 18

      10**exponent
    rescue ArgumentError, TypeError
      nil
    end

    def unit_from_description(description)
      return "minor" if description.match?(/kopeck|копейк|minor/i)
      return "major" if description.match?(/major|руб(?:л|.|$)|ruble/i)

      nil
    end

    def subunit_from_description(description)
      return "kopecks" if description.match?(/kopeck|копейк/i)
      return "cents" if description.match?(/cents?|цент/i)
      return "mills" if description.match?(/mills?|милл/i)

      nil
    end

    def unit_from_subunit(subunit)
      return "minor" if subunit.to_s.match?(/kopeck|cent|mill|minor/i)
      return "major" if subunit.to_s.match?(/major|ruble|руб/i)

      nil
    end

    def find_money_path(schema, prefix = "")
      return nil unless schema.is_a?(Hash)

      properties = schema.fetch("properties", {})
      return [prefix, "amount"].reject(&:empty?).join(".") if properties.key?("amount")
      return [prefix, "value"].reject(&:empty?).join(".") if properties.key?("value") && properties.key?("currency")

      properties.each do |name, property|
        found = find_money_path(property, [prefix, name].reject(&:empty?).join("."))
        return found if found
      end
      nil
    end

    def first_schema_with_property(node, property_name)
      case node
      when Hash
        return node if node["properties"].is_a?(Hash) && node["properties"].key?(property_name)
        node.each_value do |value|
          found = first_schema_with_property(value, property_name)
          return found if found
        end
      when Array
        node.each do |value|
          found = first_schema_with_property(value, property_name)
          return found if found
        end
      end
      nil
    end
  end

  module StatusSemantics
    module_function

    def candidate(provider_value)
      value = provider_value.to_s.downcase
      return "approved" if value.match?(/\A(?:completed|success|succeeded|settled)\z/)
      return "rejected" if value.match?(/\A(?:failed|declined|rejected|cancelled|canceled|voided|void)\z/)
      return "in_progress" if value.match?(/\A(?:processing|pending|queued)\z/)

      nil
    end

    # OpenAPI has no standard per-enum-value description. When a provider
    # documents an unambiguous mapping in the property's description, keep it
    # as specification evidence instead of treating a familiar alias as a
    # generic guess. The explicit marker is deliberately narrow so ordinary
    # prose cannot silently resolve a critical status.
    def explicit_mappings(provider_value, description)
      description.to_s.scan(/([A-Za-z][A-Za-z0-9_.-]*)\s*:\s*canonical\s+(approved|rejected|in_progress)\b/i)
        .filter_map { |value, canonical| canonical.downcase if value == provider_value.to_s }
    end
  end

  class StatusMapper
    def initialize(defaults)
      @defaults = defaults
    end

    def analyze(facts)
      descriptions = status_values(facts.components)
      facts.operations.each do |operation|
        descriptions = merge_status_values(descriptions, status_values(operation["request_body"]))
        descriptions = merge_status_values(descriptions, status_values(operation["responses"]))
      end
      values = descriptions.keys
      mappings = values.map do |provider_value|
        evidence = Array(descriptions[provider_value])
        explicit_values = evidence.filter_map { |item| item["canonical"] }.uniq
        conflicting_values = explicit_values.length > 1 ? explicit_values : []
        spec_canonical = conflicting_values.empty? ? explicit_values.first : nil
        default_canonical = @defaults.statuses[provider_value]
        canonical = spec_canonical || default_canonical
        mapping_source = @defaults.data.fetch("status_source", "CASE_DEFAULT")
        canonical_source = spec_canonical ? "SPEC_DESCRIPTION" : mapping_source
        mapping = {
          "provider_value" => provider_value,
          "canonical_value" => canonical || "UNKNOWN",
          "evidence_sources" => ["SPEC_FACT", canonical ? canonical_source : "UNKNOWN"],
          "decision" => canonical ? "ACCEPT" : "REVIEW_REQUIRED"
        }
        if conflicting_values.any?
          mapping["canonical_value"] = "UNKNOWN"
          mapping["decision"] = "REVIEW_REQUIRED"
          mapping["conflicts"] = [{
            "provider_value" => provider_value,
            "canonical_values" => conflicting_values,
            "evidence" => evidence.select { |item| item["canonical"] }.map(&:dup)
          }]
        elsif canonical.nil? && (candidate = StatusSemantics.candidate(provider_value))
          mapping["candidate_canonical_value"] = candidate
          mapping["candidate_source"] = "BUILTIN_RULE"
          mapping["decision"] = "REVIEW_REQUIRED"
        elsif canonical.nil?
          mapping["decision"] = "UNKNOWN"
        end
        mapping
      end
      complete = !mappings.empty? && mappings.all? { |mapping| mapping["decision"] == "ACCEPT" }
      unresolved = mappings.select { |mapping| mapping["canonical_value"] == "UNKNOWN" }
      ambiguous = unresolved.any? { |mapping| mapping.key?("candidate_canonical_value") }
      conflicts = mappings.flat_map { |mapping| Array(mapping["conflicts"]) }
      decision_evidence = [Evidence.new(source: "SPEC_FACT", locations: ["#/components/schemas/*/properties/status/enum"], excerpt: values.join(", "))]
      has_explicit_description = descriptions.values.any? { |evidence| Array(evidence).any? { |item| item["canonical"] } }
      decision_evidence << Evidence.new(source: "SPEC_DESCRIPTION", locations: ["#/components/schemas/*/properties/status/description"], excerpt: "explicit canonical status mappings") if has_explicit_description
      decision_evidence << Evidence.new(source: @defaults.data.fetch("status_source", "CASE_DEFAULT"), locations: ["organizer_case_qa.statuses"], excerpt: "status mapping for this workspace") if @defaults.statuses.any?
      decision_evidence << Evidence.new(source: "SPEC_DESCRIPTION", locations: ["#/components/schemas/*/properties/status/description"], excerpt: "conflicting explicit canonical status mappings") if conflicts.any?
      decision_outcome = if conflicts.any?
                           "REVIEW_REQUIRED"
                         elsif complete
                           "ACCEPT"
                         elsif ambiguous
                           "REVIEW_REQUIRED"
                         else
                           "UNKNOWN"
                         end
      decision_severity = if conflicts.any?
                            "WARNING"
                          elsif complete
                            "INFO"
                          elsif ambiguous
                            "WARNING"
                          else
                            "BLOCKING"
                          end
      decision_rationale = if conflicts.any?
                           "one or more provider statuses have contradictory explicit canonical mappings"
                         elsif complete
                             has_explicit_description ? "every provider status has an explicit canonical mapping in OpenAPI descriptions" : "every provider status has an explicit case-default canonical mapping"
                           elsif ambiguous
                             "one or more provider statuses have plausible but unconfirmed terminal aliases"
                           else
                             "one or more provider statuses lack a confirmed canonical mapping"
                           end
      decision = Decision.new(
        id: "status:provider-map",
        outcome: decision_outcome,
        severity: decision_severity,
        candidate: mappings,
        evidence: decision_evidence,
        rationale: decision_rationale,
        conflicts: conflicts
      )
      AnalysisResult.new(section: mappings, decisions: [decision])
    end

    private

    def status_values(node, found = {}, path = "#")
      case node
      when Hash
        %w[status state phase].each do |name|
          property = node.dig("properties", name)
          status = property.is_a?(Hash) ? property["enum"] : nil
          next unless status.is_a?(Array) && !status.empty?

          status.each do |provider_value|
            key = provider_value.to_s
            entry = { "canonical" => nil, "source" => "SPEC_FACT", "location" => "#{path}/properties/#{name}/enum" }
            explicit_values = StatusSemantics.explicit_mappings(provider_value, property["description"])
            if explicit_values.any?
              explicit_values.each do |canonical|
                found[key] ||= []
                found[key] << entry.merge("canonical" => canonical, "source" => "SPEC_DESCRIPTION", "location" => "#{path}/properties/#{name}/description")
              end
            else
              found[key] ||= []
              found[key] << entry
            end
          end
        end
        node.each { |key, value| status_values(value, found, "#{path}/#{key}") }
      when Array
        node.each_with_index { |value, index| status_values(value, found, "#{path}/#{index}") }
      end
      found
    end

    def merge_status_values(left, right)
      right.each do |provider_value, evidence|
        left[provider_value] ||= []
        left[provider_value].concat(Array(evidence))
      end
      left
    end
  end

  class WebhookAnalyzer
    def initialize(defaults, status_section)
      @defaults = defaults
      @status_section = status_section
    end

    def analyze(facts)
      operation = facts.operations.find do |item|
        item["source_kind"] == "webhook"
      end
      operation ||= facts.operations.find do |item|
        item["method"] == "POST" && (item["path"].to_s.downcase.match?(/webhook|callback|notification/) || item["operation_id"].to_s.downcase.match?(/webhook|callback|notify|notification/) || Array(item["parameters"]).any? { |parameter| parameter["name"].to_s.downcase.include?("signature") })
      end
      if operation.nil?
        decision = Decision.new(id: "webhook:endpoint", outcome: "ACCEPT", severity: "WARNING", candidate: nil, evidence: [Evidence.new(source: "SPEC_FACT", locations: ["#/paths", "#/webhooks"], excerpt: "no callback endpoint; polling-only provider")], rationale: "no webhook endpoint was discovered; preserve polling-only integration")
        return AnalysisResult.new(section: { "mode" => "polling_only", "decision" => "ACCEPT", "endpoint" => nil }, decisions: [decision])
      end
      signature_parameter = Array(operation["parameters"]).find { |parameter| parameter["name"].to_s.downcase.include?("signature") }
      signature_required = signature_parameter && signature_parameter.fetch("required", false)
      description = [operation["description"], signature_parameter && signature_parameter["description"]].compact.join(" ")
      algorithm = description.match?(/HMAC-SHA256/i) ? "HMAC-SHA256" : nil
      raw_body = @defaults.webhook.key?("raw_body") ? @defaults.webhook["raw_body"] : (description.match?(/raw\s+body|сырое\s+тело/i) ? true : nil)
      encoding = @defaults.webhook["signature_encoding"] || (description.match?(/\bhex(?:adecimal)?\b/i) ? "hex" : (description.match?(/\bbase64\b/i) ? "base64" : nil))
      events = event_enums(facts.components).flatten
      facts.operations.each do |item|
        events.concat(event_enums(item["request_body"]).flatten)
        events.concat(event_enums(item["responses"]).flatten)
      end
      events = events.uniq
      event_map = events.each_with_object({}) do |event, result|
        provider_status = event.to_s.split(".").last
        mapping = @status_section.find { |item| item["provider_value"] == provider_status }
        result[event] = mapping ? mapping["canonical_value"] : "UNKNOWN"
      end
      webhook_properties = operation.dig("request_body", "content", "application/json", "schema", "properties") || {}
      identifier_field = webhook_properties.keys.find { |name| name.to_s.match?(/(?:^|_)id\z/i) } || "id"
      base_complete = signature_parameter && signature_required && !raw_body.nil? && encoding && !events.empty?
      unknown_event = event_map.any? { |event, value| value == "UNKNOWN" && StatusSemantics.candidate(event.to_s.split(".").last).nil? }
      ambiguous_event = event_map.any? { |event, value| value == "UNKNOWN" && StatusSemantics.candidate(event.to_s.split(".").last) }
      complete = algorithm && base_complete && !unknown_event && !ambiguous_event
      outcome = if complete
                  "ACCEPT"
                elsif base_complete && !unknown_event
                  "REVIEW_REQUIRED"
                else
                  operation && signature_parameter ? "REVIEW_REQUIRED" : "UNKNOWN"
                end
      severity = complete ? "INFO" : (outcome == "REVIEW_REQUIRED" ? (algorithm && raw_body && encoding ? "WARNING" : "BLOCKING") : "BLOCKING")
      evidence = []
      escaped_path = operation["path"].gsub("/", "~1")
      evidence << Evidence.new(source: "SPEC_DESCRIPTION", locations: ["#/paths/#{escaped_path}/post/description", "#/paths/#{escaped_path}/post/parameters"], excerpt: description)
      evidence << Evidence.new(source: @defaults.webhook.fetch("source", "CASE_DEFAULT"), locations: ["organizer_case_qa.webhook"], excerpt: "raw body and #{encoding} signature encoding") unless @defaults.webhook.empty?
      decision = Decision.new(id: "webhook:signature", outcome: outcome, severity: severity, candidate: { "algorithm" => algorithm, "encoding" => encoding, "events" => event_map }, evidence: evidence, rationale: complete ? "endpoint, signature header, algorithm, raw body, encoding and event outcomes are represented" : "webhook verification requires endpoint and complete signature/event semantics")
      section = {
        "endpoint" => "#{operation["method"]} #{operation["path"]}",
        "signature" => { "algorithm" => algorithm || "UNKNOWN", "header" => signature_parameter && signature_parameter["name"], "required" => !!signature_required, "input" => raw_body ? "raw_body" : "UNKNOWN", "encoding" => encoding || "UNKNOWN" },
        "events" => event_map,
        "identifier_field" => identifier_field,
        "raw_body_required" => raw_body.nil? ? "UNKNOWN" : raw_body,
        "decision" => outcome
      }
      AnalysisResult.new(section: section, decisions: [decision])
    end

    private

    def event_enums(node, found = [])
      case node
      when Hash
        event = node.dig("properties", "event", "enum")
        found << Array(event) if event.is_a?(Array) && !event.empty?
        node.each_value { |value| event_enums(value, found) }
      when Array
        node.each { |value| event_enums(value, found) }
      end
      found
    end
  end

  class IdempotencyAnalyzer
    def initialize(adapter_policy, defaults = nil)
      @adapter_policy = adapter_policy
      @defaults = defaults
    end

    def analyze(facts)
      operation = facts.operations.find { |item| item["operation_id"].to_s.downcase.match?(/create|initiat|submit/) }
      operation ||= facts.operations.find do |item|
        next false unless item["method"] == "POST"

        schema = item.dig("request_body", "content", "application/json", "schema") || {}
        schema.fetch("properties", {}).keys.any? { |name| name.to_s.match?(/amount|sum|total/) }
      end
      parameter = operation && Array(operation["parameters"]).find { |item| item["name"].to_s.downcase.include?("idempot") || item["description"].to_s.downcase.match?(/idempot|duplicate|\u0438\u0434\u0435\u043c\u043f\u043e\u0442\u0435\u043d\u0442/) }
      resolution = @defaults&.idempotency || {}
      resolved_header = resolution.fetch("header", nil)
      resolved_required = resolution.fetch("spec_required", false)
      resolved_explicitly = !resolution.empty?
      required = parameter ? parameter.fetch("required", false) : (resolved_explicitly ? resolved_required : nil)
      present = !parameter.nil?
      decision = Decision.new(
        id: "idempotency:header",
        outcome: present || resolved_explicitly ? "ACCEPT" : "REVIEW_REQUIRED",
        severity: present || resolved_explicitly ? "INFO" : "WARNING",
        candidate: { "header" => parameter ? parameter["name"] : resolved_header, "spec_required" => required },
        evidence: [Evidence.new(source: present ? "SPEC_FACT" : (resolution["source"] || "UNKNOWN"), locations: ["#/components/parameters/IdempotencyKey"], excerpt: parameter ? parameter["description"] : (resolved_explicitly ? "human-confirmed absence or shape of idempotency header" : nil))],
        rationale: present ? "header presence and requiredness are read from the OpenAPI parameter" : (resolved_explicitly ? "idempotency behavior was explicitly confirmed for this workspace" : "no explicit idempotency parameter was found")
      )
      section = {
        "header" => parameter ? parameter["name"] : resolved_header,
        "spec_required" => required,
        "spec_evidence_source" => present ? "SPEC_FACT" : (resolution["source"] || "UNKNOWN"),
        "adapter_policy" => { "send_header" => @adapter_policy, "provenance" => "ADAPTER_POLICY" },
        "retry_policy" => { "name" => present ? "preserve_same_key" : "unknown", "provenance" => "ADAPTER_POLICY" }
      }
      AnalysisResult.new(section: section, decisions: [decision])
    end
  end

  class ConditionalAnalyzer
    def analyze(facts)
      conditionals = []
      unresolved = []
      facts.components.fetch("schemas", {}).each do |schema_name, schema|
        schema.fetch("properties", {}).each do |property_name, property|
          description = property["description"].to_s
          next unless description.match?(/required|mandatory|\u043e\u0431\u044f\u0437\u0430\u0442\u0435\u043b\u0435\u043d/i)

          type_match = description.match(/type\s*=\s*([a-z0-9_-]+)/i)
          if type_match
            conditionals << {
              "predicate" => "#{schema_name.to_s.downcase}.type == #{type_match[1]}",
              "required" => ["#{schema_name.to_s.downcase}.#{property_name}"],
              "evidence_sources" => ["SPEC_DESCRIPTION"],
              "decision" => "ACCEPT"
            }
          else
            unresolved << { "schema" => schema_name, "property" => property_name, "description" => description }
          end
        end
      end
      locations = facts.components.fetch("schemas", {}).keys.sort.map { |name| "#/components/schemas/#{name}/properties" }
      complete = unresolved.empty?
      decision = Decision.new(
        id: "conditions:conditional-required",
        outcome: complete ? "ACCEPT" : "REVIEW_REQUIRED",
        severity: complete ? "INFO" : "WARNING",
        candidate: { "parsed" => conditionals, "unresolved" => unresolved },
        evidence: [Evidence.new(source: "SPEC_DESCRIPTION", locations: locations, excerpt: "conditional required fields in descriptions")],
        rationale: complete ? "all conditional phrases were parsed without relying on a fixed branch count" : "one or more conditional phrases need review"
      )
      AnalysisResult.new(section: conditionals, decisions: [decision])
    end
  end

  class FieldMapper
    def initialize(profile, defaults)
      @profile = profile
      @defaults = defaults
    end

    def analyze(facts, money)
      create_operation = facts.operations.find { |operation| operation["method"] == "POST" && operation["operation_id"].to_s.match?(/create|initiat|submit/i) }
      create_operation ||= facts.operations.find do |operation|
        next false unless operation["method"] == "POST"

        schema = operation.dig("request_body", "content", "application/json", "schema") || {}
        schema.fetch("properties", {}).keys.any? { |name| name.to_s.match?(/amount|sum|total/) }
      end
      schema = create_operation && create_operation.dig("request_body", "content", "application/json", "schema")
      mappings = Array(@defaults.data["field_mappings"])
      mappings = inferred_mappings(schema, money, facts) if mappings.empty?
      mappings = mappings.map { |mapping| enrich(mapping, money, facts, schema) }
      complete = !mappings.empty? && mappings.all? { |mapping| mapping["decision"] == "ACCEPT" }
      decision = Decision.new(
        id: "fields:create-request",
        outcome: complete ? "ACCEPT" : (mappings.empty? ? "UNKNOWN" : "REVIEW_REQUIRED"),
        severity: complete ? "INFO" : "BLOCKING",
        candidate: mappings,
        evidence: [Evidence.new(source: mappings.any? { |item| item["provenance"] == "CASE_DEFAULT" } ? "CASE_DEFAULT" : "SPEC_FACT", locations: ["#/paths/*/requestBody", "#/components/schemas/*/properties"], excerpt: "request and response field mappings")],
        rationale: complete ? "canonical fields have explicit direct or transformed mappings" : "one or more canonical field mappings are unresolved"
      )
      AnalysisResult.new(section: mappings, decisions: [decision])
    end

    private

    def inferred_mappings(schema, money, facts)
      properties = schema.is_a?(Hash) ? schema.fetch("properties", {}) : {}
      required = schema.is_a?(Hash) ? Array(schema["required"]) : []
      nested_name, nested_node = properties.find do |_name, node|
        node.is_a?(Hash) && node["properties"].is_a?(Hash) && node["properties"].keys.any? { |name| name.to_s.match?(/\A(?:value|amount)\z/i) }
      end
      nested_money = nested_node.is_a?(Hash) ? nested_node.fetch("properties", {}) : {}
      nested_value_name = nested_money.keys.find { |name| name.to_s.match?(/\A(?:value|amount)\z/i) }
      provider_fields = {
        "amount" => money.dig("provider", "field")&.sub("request.", "") || (properties.key?("amount") ? "amount" : (nested_name && nested_value_name ? "#{nested_name}.#{nested_value_name}" : nil)),
        "currency" => properties.key?("currency") ? "currency" : (nested_money.key?("currency") ? "#{nested_name}.currency" : nil),
        "external_id" => semantic_property(properties, /\A(?:external_id|external_reference|client_reference|merchant_reference|reference|request_id)\z/i),
        "recipient" => semantic_property(properties, /\A(?:recipient|destination|beneficiar|beneficiary|payee)\z/i)
      }
      mappings = provider_fields.filter_map do |field, provider_field|
        next if provider_field.nil?

        provider_name = provider_field.to_s
        direct_name = provider_name.split(".").last
        amount = field == "amount"
        {
          "canonical_path" => "operation.#{field}",
          "provider_path" => "request.#{provider_name}",
          "direction" => "request",
          "transform" => amount ? money.dig("request_conversion", "operation") : "identity",
          "factor" => amount ? money.dig("request_conversion", "factor") : 1,
          "required" => required.include?(field) || (provider_name.include?(".") && required.include?(provider_name.split(".").first)) || (field == "amount" && !provider_name.nil?),
          "provenance" => "SPEC_FACT",
          "decision" => "ACCEPT"
        }
      end
      response_amount = money.dig("provider", "response_field") || "response.amount"
      response_schema = response_schema(facts)
      response_id = response_property_path(response_schema, /\A(?:id|.*_id)\z/i) || "id"
      response_status = response_property_path(response_schema, /\A(?:status|state|phase)\z/i) || "status"
      mappings.concat([
        { "canonical_path" => "operation.provider_operation_id", "provider_path" => "response.#{response_id}", "direction" => "response", "transform" => "identity", "factor" => 1, "required" => false, "provenance" => "SPEC_FACT", "decision" => "ACCEPT" },
        { "canonical_path" => "operation.status", "provider_path" => "response.#{response_status}", "direction" => "response", "transform" => "status_map", "factor" => 1, "required" => false, "provenance" => "SPEC_FACT", "decision" => "ACCEPT" },
        { "canonical_path" => "operation.amount", "provider_path" => response_amount, "direction" => "response", "transform" => money.dig("response_conversion", "operation"), "factor" => money.dig("response_conversion", "factor"), "required" => false, "provenance" => "SPEC_FACT", "decision" => "ACCEPT" }
      ])
      mappings
    end

    def response_schema(facts)
      operation = facts.operations.find { |item| item["method"] == "GET" && item["responses"].values.any? { |response| response.dig("content", "application/json", "schema") } }
      operation && operation["responses"].values.map { |response| response.dig("content", "application/json", "schema") }.compact.first
    end

    def response_property_path(schema, pattern, prefix = "")
      return nil unless schema.is_a?(Hash)

      schema.fetch("properties", {}).each do |name, property|
        path = [prefix, name].reject(&:empty?).join(".")
        return path if name.to_s.match?(pattern)

        nested = response_property_path(property, pattern, path)
        return nested if nested
      end
      nil
    end

    def enrich(mapping, money, facts, request_schema)
      result = Util.deep_dup(mapping)
      result["direction"] ||= "request"
      result["transform"] ||= "identity"
      result["factor"] = money.dig("request_conversion", "factor") if result["canonical_path"] == "operation.amount" && result["direction"] == "request"
      result["factor"] = money.dig("response_conversion", "factor") if result["canonical_path"] == "operation.amount" && result["direction"] == "response"
      result["provenance"] ||= "CASE_DEFAULT"
      result["decision"] ||= "ACCEPT"
      if result["transform"].to_s == "unresolved" || (result["canonical_path"] == "operation.amount" && result["factor"].nil?)
        result["decision"] = "REVIEW_REQUIRED"
      end
      unless provider_path_present?(result["provider_path"], facts, request_schema)
        result["decision"] = "REVIEW_REQUIRED"
        result["resolution_issue"] = "provider field is absent from the resolved schema"
      end
      result
    end

    def provider_path_present?(path, facts, request_schema)
      scope, field = path.to_s.split(".", 2)
      return false if field.to_s.empty?

      if scope == "request"
        path_exists_in_schema?(request_schema, field)
      elsif scope == "response"
        facts.operations.any? do |operation|
          operation["responses"].values.any? do |response|
            schema = response.dig("content", "application/json", "schema")
            path_exists_in_schema?(schema, field)
          end
        end
      else
        false
      end
    end

    def path_exists_in_schema?(schema, field_path)
      field_path.to_s.split(".").reduce(schema) do |current, name|
        break nil unless current.is_a?(Hash)

        current.fetch("properties", {})[name]
      end
    end

    def semantic_property(properties, pattern)
      properties.keys.find { |name| name.to_s.match?(pattern) }
    end
  end

  class HostProjectionAnalyzer
    def initialize(profile)
      @profile = profile
    end

    def analyze(facts)
      projection = @profile.host_projection
      requisite = projection.fetch("requisite", {})
      branches = requisite.fetch("branches", {})
      return AnalysisResult.new(section: { "requirements" => [], "decision" => "ACCEPT" }, decisions: []) if branches.empty?

      operation = facts.operations.find { |item| item["method"] == "POST" && item["operation_id"].to_s.match?(/create|initiat|submit/i) }
      operation ||= facts.operations.find { |item| item["method"] == "POST" }
      schema = operation && operation.dig("request_body", "content", "application/json", "schema")
      provider_path = requisite.fetch("provider_path", "recipient").sub("request.", "")
      provider_schema = path_schema(schema, provider_path)
      return AnalysisResult.new(section: { "requirements" => [], "decision" => "ACCEPT" }, decisions: []) unless provider_schema.is_a?(Hash) && provider_schema["properties"].is_a?(Hash)

      required_fields = Array(provider_schema["required"]).map(&:to_s)
      all_configured_fields = branches.values.flat_map { |branch| branch.is_a?(Hash) ? branch.fetch("fields", {}).keys.map(&:to_s) : [] }.uniq
      requirements = branches.filter_map do |branch_name, branch|
        next unless branch.is_a?(Hash)

        branch_fields = branch.fetch("fields", {}).keys.map(&:to_s)
        branch_anchor = (branch_fields & required_fields).any?
        configured_fields = branch_anchor ? branch_fields : all_configured_fields
        required_fields.reject { |field| field == "type" || configured_fields.include?(field) }.map do |field|
          {
            "branch" => branch_name.to_s,
            "provider_field" => field,
            "provider_path" => "request.#{provider_path}.#{field}",
            "host_source" => requisite.fetch("source", "operation.payout_requisite"),
            "mapping" => nil,
            "generation_impact" => "BLOCKING",
            "todo" => "provider requires field `#{field}` for #{branch_name}. Host mapping is not known. Confirm source inside operation.payout_requisite or extend BaseServiceProfile."
          }
        end
      end.flatten
      return AnalysisResult.new(section: { "requirements" => [], "decision" => "ACCEPT" }, decisions: []) if requirements.empty?

      location = "#/paths/#{operation["path"].to_s.gsub("/", "~1")}/#{operation["method"].to_s.downcase}/requestBody/content/application~1json/schema/properties/#{provider_path.gsub(".", "/")}/required"
      decision = Decision.new(
        id: "host:requisite-mapping",
        outcome: "REVIEW_REQUIRED",
        severity: "BLOCKING",
        candidate: requirements,
        evidence: [Evidence.new(source: "SPEC_FACT", locations: [location], excerpt: "required provider requisite fields without a declared host projection")],
        rationale: "required provider requisite fields must have an explicit operation.payout_requisite mapping before generation"
      )
      AnalysisResult.new(section: { "requirements" => requirements, "decision" => "REVIEW_REQUIRED" }, decisions: [decision])
    end

    private

    def path_schema(schema, path)
      path.to_s.split(".").reduce(schema) do |current, name|
        break nil unless current.is_a?(Hash)

        current.fetch("properties", {})[name]
      end
    end
  end

  class ConstraintAnalyzer
    def analyze(facts, money)
      operation = facts.operations.find { |item| item["method"] == "POST" && item["operation_id"].to_s.match?(/create|initiat|submit/i) }
      operation ||= facts.operations.find do |item|
        next false unless item["method"] == "POST"

        schema = item.dig("request_body", "content", "application/json", "schema") || {}
        schema.fetch("properties", {}).keys.any? { |name| name.to_s.match?(/amount|sum|total/) }
      end
      schema = operation && operation.dig("request_body", "content", "application/json", "schema")
      constraints = []
      walk(schema, "request", constraints) if schema.is_a?(Hash)
      invalid_patterns = constraints.filter_map do |constraint|
        pattern = constraint["pattern"]
        next if pattern.nil?

        begin
          raise RegexpError, "pattern exceeds safety limit" if pattern.to_s.length > 1024
          raise RegexpError, "nested quantifiers are not accepted" if pattern.to_s.match?(/\([^)]*[+*][^)]*\)[+*]/)

          Regexp.new(pattern.to_s)
          nil
        rescue RegexpError, ArgumentError => e
          constraint["pattern_valid"] = false
          constraint["pattern_error"] = e.message
          constraint
        end
      end
      provider_amount_path = money.dig("provider", "field") || "request.amount"
      constraints.each do |constraint|
        next unless constraint["path"] == provider_amount_path && constraint.key?("minimum")

        factor = money.dig("response_conversion", "factor_decimal") || money.dig("response_conversion", "factor")
        converted = factor ? BigDecimal(constraint["minimum"].to_s) * BigDecimal(factor.to_s) : nil
        constraint["host_minimum"] = if converted.nil?
                                        nil
                                      elsif converted.frac.zero?
                                        converted.to_i
                                      else
                                        converted.to_s("F")
                                      end
      end
      present = schema.is_a?(Hash)
      decision = Decision.new(
        id: "constraints:create-request",
        outcome: invalid_patterns.empty? ? (present ? "ACCEPT" : "UNKNOWN") : "REVIEW_REQUIRED",
        severity: invalid_patterns.empty? ? (present ? "INFO" : "BLOCKING") : "BLOCKING",
        candidate: constraints,
        evidence: [Evidence.new(source: "SPEC_FACT", locations: ["#/paths/*/requestBody/content/application~1json/schema"], excerpt: "request constraints")],
        rationale: if invalid_patterns.any?
                     "one or more provider regex patterns are invalid or exceed the runtime safety limit"
                   elsif present
                     "structured request constraints are preserved for generated validation"
                   else
                     "create request schema is missing"
                   end
      )
      AnalysisResult.new(section: constraints, decisions: [decision])
    end

    private

    def walk(schema, prefix, result)
      return unless schema.is_a?(Hash)

      properties = schema.fetch("properties", {})
      required = Array(schema["required"])
      properties.each do |name, property|
        path = "#{prefix}.#{name}"
        entry = { "path" => path, "required" => required.include?(name), "provenance" => "SPEC_FACT" }
        %w[type format minimum maximum minLength maxLength pattern enum].each { |key| entry[key] = property[key] if property.key?(key) }
        alternatives = property["oneOf"] || property["anyOf"]
        entry["alternatives"] = alternatives.map { |item| item["type"] || item.dig("properties")&.keys }.compact if alternatives.is_a?(Array)
        result << entry
        walk(property, path, result)
      end
    end
  end

  class ErrorAnalyzer
    def analyze(facts)
      entries = facts.operations.flat_map do |operation|
        operation["responses"].map do |status, response|
          error_response = status.to_s.to_i >= 400
          schema_codes = []
          codes = example_codes(response).uniq
          category = category_for_status(status.to_s)
          {
            "operation_id" => operation["operation_id"],
            "http_status" => status.to_s,
            "provider_codes" => codes.map { |code| code_entry(code, status.to_s, schema_codes.include?(code), operation["method"]) },
            "canonical_category" => category,
            "retryable" => status.to_s == "429",
            "description" => response["description"],
            "retry_after_header" => status.to_s == "429" ? "Retry-After" : nil,
            "evidence_sources" => ["SPEC_FACT", "SPEC_EXAMPLE"]
          }
        end
      end
      decision = Decision.new(
        id: "errors:provider-model",
        outcome: entries.empty? ? "UNKNOWN" : "ACCEPT",
        severity: entries.empty? ? "BLOCKING" : "INFO",
        candidate: entries,
        evidence: [Evidence.new(source: "SPEC_FACT", locations: ["#/paths/*/responses", "#/components/schemas/*/properties/code/enum"], excerpt: "HTTP statuses and provider error codes")],
        rationale: entries.empty? ? "no response model was found" : "known and example-only provider codes are represented with conservative retry policies"
      )
      AnalysisResult.new(section: entries, decisions: [decision])
    end

    private

    def code_entry(code, status, known, method)
      numeric = status.to_i
      category, retryable, action = if numeric == 429
                                      ["rate_limit_exceeded", true, method.to_s.upcase == "POST" ? "retry_after_with_same_idempotency_key" : "retry_after"]
                                    elsif numeric == 401
                                      ["unauthorized", false, "refresh_credentials_or_review"]
                                    elsif numeric == 402
                                      ["insufficient_balance", false, "review_provider_balance"]
                                    elsif numeric == 409
                                      ["conflict", false, "inspect_existing_operation"]
                                    elsif numeric == 404
                                      ["not_found", false, "review_identifier"]
                                    elsif numeric >= 500
                                      ["internal_error", false, method.to_s.upcase == "GET" ? "review_safe_read_retry" : "manual_retry_review"]
                                    elsif numeric >= 400
                                      ["validation_error", false, "correct_request"]
                                    else
                                      ["success", false, "none"]
                                    end
      { "code" => code, "known_to_schema" => known, "category" => category, "retryable" => retryable, "action" => action, "unknown_code_policy" => known ? "mapped" : "preserve_and_review" }
    end

    def category_for_status(status)
      numeric = status.to_i
      return "rate_limit_exceeded" if numeric == 429
      return "unauthorized" if numeric == 401
      return "insufficient_balance" if numeric == 402
      return "conflict" if numeric == 409
      return "not_found" if numeric == 404
      return "internal_error" if numeric >= 500
      return "validation_error" if numeric >= 400

      "unknown_provider_error"
    end

    def example_codes(response)
      values = []
      walk_examples(response, values)
      values.uniq
    end

    def walk_examples(node, values)
      case node
      when Hash
        values << node["code"] if node["code"].is_a?(String)
        node.each_value { |value| walk_examples(value, values) }
      when Array
        node.each { |value| walk_examples(value, values) }
      end
    end

    def error_codes(node, found = [])
      case node
      when Hash
        direct = node.dig("properties", "code", "enum")
        found.concat(Array(direct)) if direct.is_a?(Array)
        node.each_value { |value| error_codes(value, found) }
      when Array
        node.each { |value| error_codes(value, found) }
      end
      found
    end
  end

  class ParameterAnalyzer
    def analyze(facts)
      auth_names = facts.security_schemes.values.filter_map do |scheme|
        scheme["name"] if scheme.is_a?(Hash) && scheme["type"] == "apiKey"
      end
      features = facts.operations.flat_map do |operation|
        webhook_operation = operation["source_kind"] == "webhook" || operation["path"].to_s.match?(/webhook|callback|notification/i)
        Array(operation["parameters"]).filter_map do |parameter|
          next unless parameter.is_a?(Hash)
          location = parameter["in"].to_s
          next unless %w[query header cookie].include?(location)
          name = parameter["name"].to_s
          next if auth_names.include?(name)
          next if name.match?(/idempot/i)
          next if webhook_operation && name.match?(/signature/i)

          required = parameter["required"] == true
          {
            "location" => "#/paths/#{operation["path"].to_s.gsub("/", "~1")}/#{operation["method"].to_s.downcase}/parameters/#{name}",
            "feature" => "required_provider_parameter",
            "in" => location,
            "name" => name,
            "required" => required,
            "reason" => required ? "required provider parameter has no canonical host/config mapping" : "optional provider parameter is preserved but not emitted by the canonical adapter",
            "severity" => required ? "BLOCKING" : "WARNING",
            "generation_impact" => required ? "BLOCKING" : "NON_BLOCKING"
          }
        end
      end
      required = features.select { |item| item["required"] }
      decision = Decision.new(
        id: "parameters:provider-inputs",
        outcome: required.empty? ? "ACCEPT" : "REVIEW_REQUIRED",
        severity: required.empty? ? "INFO" : "BLOCKING",
        candidate: features,
        evidence: [Evidence.new(source: "SPEC_FACT", locations: features.map { |item| item["location"] }, excerpt: "provider query/header/cookie parameters")],
        rationale: required.empty? ? "no unmapped required provider parameter was found" : "required provider parameters need an explicit host/config mapping before generation"
      )
      AnalysisResult.new(section: features, decisions: features.empty? ? [] : [decision])
    end
  end

  class UnsupportedFeatureAnalyzer
    def analyze(facts)
      features = []
      facts.security_schemes.each do |name, scheme|
        next if (scheme["type"] == "apiKey" && %w[header query].include?(scheme["in"])) || (scheme["type"] == "http" && scheme["scheme"].to_s.casecmp?("bearer"))

        features << {
          "location" => "#/components/securitySchemes/#{name}",
          "feature" => scheme["type"].to_s,
          "reason" => "authentication scheme is outside the supported deterministic transport boundary",
          "severity" => "BLOCKING",
          "generation_impact" => "BLOCKING"
        }
      end
      facts.operations.each do |operation|
        media_types = operation.dig("request_body", "content")
        if media_types.is_a?(Hash) && !media_types.empty? && !media_types.key?("application/json")
          media_types.keys.each do |media_type|
            features << {
              "location" => "#/paths/#{operation["path"].to_s.gsub("/", "~1")}/#{operation["method"].to_s.downcase}/requestBody/content/#{media_type}",
              "feature" => "#{media_type.gsub("/", "_")}_request",
              "reason" => "canonical generated transport only defines JSON request projection",
              "severity" => "BLOCKING",
              "generation_impact" => "BLOCKING"
            }
          end
        end
        next unless operation["source_kind"] == "webhook"
        next if Array(operation["parameters"]).any? { |parameter| parameter["name"].to_s.match?(/signature/i) }

        features << {
          "location" => "#/paths/#{operation["path"].to_s.gsub("/", "~1")}/#{operation["method"].to_s.downcase}",
          "feature" => "callback_without_signature",
          "reason" => "callback endpoint has no declared signature input",
          "severity" => "REVIEW_REQUIRED",
          "generation_impact" => "BLOCKING"
        }
      end
      decision = Decision.new(
        id: "unsupported:features",
        outcome: features.empty? ? "ACCEPT" : "REVIEW_REQUIRED",
        severity: features.empty? ? "INFO" : (features.any? { |item| item["generation_impact"] == "BLOCKING" } ? "BLOCKING" : "WARNING"),
        candidate: features,
        evidence: [Evidence.new(source: "SPEC_FACT", locations: features.map { |item| item["location"] }, excerpt: "unsupported or unresolved OpenAPI features")],
        rationale: features.empty? ? "no unsupported critical feature was found" : "unsupported or unresolved provider features are preserved as diagnostics"
      )
      AnalysisResult.new(section: features, decisions: features.empty? ? [] : [decision])
    end
  end

  class AnalyzerEngine
    def initialize(profile:, defaults:, adapter_policy: "if_available")
      @profile = profile
      @defaults = defaults
      @adapter_policy = adapter_policy
    end

    def analyze(facts)
      results = {}
      decisions = []
      analyzers = [
        [:operations, OperationMapper.new(@profile)],
        [:auth, AuthAnalyzer.new],
        [:money, MoneyAnalyzer.new(@profile, @defaults)],
        [:statuses, StatusMapper.new(@defaults)],
        [:idempotency, IdempotencyAnalyzer.new(@adapter_policy, @defaults)],
        [:conditionals, ConditionalAnalyzer.new]
      ]
      analyzers.each do |key, analyzer|
        result = analyzer.analyze(facts)
        results[key] = result.section
        decisions.concat(result.decisions)
      end
      field_result = FieldMapper.new(@profile, @defaults).analyze(facts, results.fetch(:money))
      results[:field_mappings] = field_result.section
      decisions.concat(field_result.decisions)
      host_projection_result = HostProjectionAnalyzer.new(@profile).analyze(facts)
      results[:host_projection] = host_projection_result.section
      decisions.concat(host_projection_result.decisions)
      constraint_result = ConstraintAnalyzer.new.analyze(facts, results.fetch(:money))
      results[:constraints] = constraint_result.section
      decisions.concat(constraint_result.decisions)
      webhook_result = WebhookAnalyzer.new(@defaults, results.fetch(:statuses)).analyze(facts)
      results[:webhook] = webhook_result.section
      decisions.concat(webhook_result.decisions)
      error_result = ErrorAnalyzer.new.analyze(facts)
      results[:errors] = error_result.section
      decisions.concat(error_result.decisions)
      parameter_result = ParameterAnalyzer.new.analyze(facts)
      unsupported_result = UnsupportedFeatureAnalyzer.new.analyze(facts)
      results[:unsupported_features] = parameter_result.section + unsupported_result.section
      decisions.concat(parameter_result.decisions)
      decisions.concat(unsupported_result.decisions)
      AnalysisBundle.new(results, decisions)
    end
  end

end
