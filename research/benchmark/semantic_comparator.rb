# frozen_string_literal: true

# Independent semantic validation for benchmark output.
#
# This file deliberately consumes only hand-authored expectations and the
# produced Blueprint. It does not call analyzers, reuse expected decisions from
# production code, or derive ground truth from a Blueprint.
require "bigdecimal"

module SemanticBenchmark
  class Comparator
    UNKNOWN_VALUES = [nil, "", "UNKNOWN", "unknown", "unresolved"].freeze

    def compare(expected_decision:, expected_case:, actual_decision:, blueprint:, generation:, error: nil)
      expected_case = expected_case || {}
      expected_semantics = expected_case.fetch("semantics", {})
      safety = expected_case.fetch("safety", {})

      decision_check = check("decision", actual_decision == expected_decision, expected_decision, actual_decision)
      semantic_checks = compare_semantics(expected_semantics, blueprint)
      safety_checks = compare_safety(safety, expected_decision, actual_decision, blueprint, generation, error)
      generation_check = compare_generation(expected_decision, generation)
      all_checks = [decision_check, *semantic_checks, *safety_checks, generation_check]

      {
        "passed" => all_checks.all? { |item| item["passed"] },
        "decision_pass" => decision_check["passed"],
        "semantic_pass" => semantic_checks.all? { |item| item["passed"] },
        "safety_pass" => safety_checks.all? { |item| item["passed"] },
        "generation_runtime_pass" => generation_check["passed"],
        "semantic_areas" => semantic_areas(semantic_checks),
        "checks" => all_checks,
        "failed_checks" => all_checks.reject { |item| item["passed"] }.map { |item| item["name"] }
      }
    end

    private

    def compare_semantics(expected, blueprint)
      return [] if expected.empty?
      return [check("semantic.blueprint_present", false, "Blueprint", nil, note: "semantic expectations cannot be checked after compiler error")] unless blueprint

      checks = []
      expected.each do |area, subset|
        case area
        when "operations"
          checks.concat(compare_operations(subset, blueprint.fetch("operations", [])))
        when "money"
          checks.concat(compare_subset(subset, blueprint["money"], "semantic.money"))
        when "auth"
          checks.concat(compare_subset(subset, blueprint["auth"], "semantic.auth"))
        when "statuses"
          checks.concat(compare_statuses(subset, blueprint.fetch("statuses", [])))
        when "webhook"
          checks.concat(compare_subset(subset, blueprint["webhook"], "semantic.webhook"))
        when "idempotency"
          checks.concat(compare_subset(subset, blueprint["idempotency"], "semantic.idempotency"))
        when "field_mappings"
          checks.concat(compare_mappings(subset, blueprint.fetch("field_mappings", [])))
        when "extra_operations"
          checks.concat(compare_extra_operations(subset, blueprint.fetch("extra_operations", [])))
        when "source"
          checks.concat(compare_source(subset, blueprint["source"]))
        else
          checks << check("semantic.#{area}", false, "supported semantic area", area, note: "unknown semantic ground-truth area")
        end
      end
      checks
    end

    def compare_operations(expected, actual)
      expected.map do |canonical, subset|
        item = actual.find { |candidate| candidate["canonical"] == canonical }
        if item
          compare_subset(subset, item, "semantic.operations.#{canonical}")
        else
          [check("semantic.operations.#{canonical}", false, subset, nil, note: "canonical operation is absent")]
        end
      end.flatten
    end

    def compare_statuses(expected, actual)
      expected.map do |provider_value, canonical_value|
        item = actual.find { |candidate| candidate["provider_value"] == provider_value }
        observed = item && item["canonical_value"]
        check("semantic.statuses.#{provider_value}", observed == canonical_value, canonical_value, observed)
      end
    end

    def compare_mappings(expected, actual)
      expected.map do |subset|
        item = actual.find do |candidate|
          candidate["canonical_path"] == subset["canonical_path"] &&
            (subset["direction"].nil? || candidate["direction"] == subset["direction"])
        end
        if item
          compare_subset(subset, item, "semantic.field_mappings.#{subset["canonical_path"]}.#{subset["direction"] || "any"}")
        else
          [check("semantic.field_mappings.#{subset["canonical_path"]}", false, subset, nil, note: "mapping is absent")]
        end
      end.flatten
    end

    def compare_extra_operations(expected, actual)
      expected.map do |subset|
        item = actual.find do |candidate|
          (!subset["operation_id"].nil? && candidate["operation_id"] == subset["operation_id"]) ||
            (!subset["path"].nil? && candidate["path"] == subset["path"])
        end
        if item
          compare_subset(subset, item, "semantic.extra_operations.#{subset["operation_id"] || subset["path"]}")
        else
          [check("semantic.extra_operations.#{subset["operation_id"] || subset["path"]}", false, subset, nil, note: "extra operation is absent")]
        end
      end.flatten
    end

    def compare_source(expected, source)
      checks = []
      source ||= {}
      fingerprint_inputs = source.fetch("fingerprint_inputs", {})
      expected.fetch("resolved_files", []).each do |name|
        files = fingerprint_inputs.fetch("resolved_files", {})
        checks << check("semantic.source.resolved_files.#{name}", files.key?(name), true, files.key?(name), note: "resolved input must be part of fingerprint inputs")
      end
      checks
    end

    def compare_subset(expected, actual, path)
      return [check(path, false, expected, nil, note: "actual semantic section is absent")] unless actual.is_a?(Hash)

      expected.flat_map do |key, value|
        observed = actual[key]
        if value.is_a?(Hash)
          compare_subset(value, observed, "#{path}.#{key}")
        else
          [check("#{path}.#{key}", equivalent?(value, observed), value, observed)]
        end
      end
    end

    def compare_safety(expected, expected_decision, actual_decision, blueprint, generation, error)
      checks = []
      if expected_decision == "REVIEW_REQUIRED"
        checks << check("safety.review_decision", actual_decision == "REVIEW_REQUIRED", "REVIEW_REQUIRED", actual_decision)
        checks.concat(compare_required_decisions(expected.fetch("required_decisions", []), blueprint))
        checks.concat(compare_forbidden_resolved(expected.fetch("forbid_resolved", []), blueprint))
        checks.concat(compare_forbidden_status_mappings(expected.fetch("forbid_status_mappings", []), blueprint))
        checks << check("safety.review_generation_blocked", generation.nil? || generation["status"] == "not_attempted", "not_attempted", generation && generation["status"])
      elsif expected_decision == "UNKNOWN"
        checks << check("safety.unknown_decision", actual_decision == "UNKNOWN", "UNKNOWN", actual_decision)
        if blueprint
          unknowns = Array(blueprint["unknowns"])
          unknown_decisions = Array(blueprint["decisions"]).select { |item| item["outcome"] == "UNKNOWN" }
          checks << check("safety.unknown_preserved", !unknowns.empty? && !unknown_decisions.empty?, "reported UNKNOWN decision", { "unknowns" => unknowns.length, "unknown_decisions" => unknown_decisions.length })
        else
          checks << check("safety.unknown_error_preserved", !error.nil? && !error["message"].to_s.empty?, "compiler error diagnostic", error)
        end
        checks << check("safety.unknown_generation_blocked", generation.nil? || generation["status"] == "not_attempted", "not_attempted", generation && generation["status"])
      end
      checks
    end

    def compare_required_decisions(expected, blueprint)
      expected.map do |item|
        actual = Array(blueprint && blueprint["decisions"]).find { |candidate| candidate["decision_id"] == item["id"] }
        observed = actual && actual.slice("outcome", "severity")
        wanted = item.slice("outcome", "severity")
        check("safety.required_decision.#{item["id"]}", observed == wanted, wanted, observed)
      end
    end

    def compare_forbidden_resolved(paths, blueprint)
      paths.map do |path|
        observed = read_path(blueprint, path)
        safe = case path
               when "money.request_conversion", "money.response_conversion"
                 !observed.is_a?(Hash) || observed["status"] != "resolved"
               else
                 unknown?(observed)
               end
        check("safety.forbid_resolved.#{path}", safe, "unresolved/unknown", observed)
      end
    end

    def compare_forbidden_status_mappings(statuses, blueprint)
      statuses.map do |provider_value|
        item = Array(blueprint && blueprint["statuses"]).find { |candidate| candidate["provider_value"] == provider_value }
        observed = item && item["canonical_value"]
        check("safety.forbid_status_mapping.#{provider_value}", unknown?(observed), "UNKNOWN", observed)
      end
    end

    def compare_generation(expected_decision, generation)
      status = generation && generation["status"]
      passed = if expected_decision == "ACCEPT"
                 generation.is_a?(Hash) && status == "passed" && generation.dig("verification", "passed") != false
               else
                 generation.nil? || status == "not_attempted"
               end
      expected = expected_decision == "ACCEPT" ? "passed" : "not_attempted"
      check("generation.runtime", passed, expected, status, note: "ACCEPT requires generated verification; abstentions must not generate")
    end

    def semantic_areas(checks)
      checks.group_by do |item|
        item["name"].to_s.split(".")[1]
      end.transform_values { |items| items.all? { |item| item["passed"] } }
    end

    def read_path(object, path)
      path.to_s.split(".").reduce(object) { |current, key| current.is_a?(Hash) ? current[key] : nil }
    end

    def equivalent?(expected, actual)
      return expected == actual unless expected.is_a?(String) && actual.is_a?(Numeric)
      return BigDecimal(expected.to_s) == BigDecimal(actual.to_s) if expected.match?(/\A-?\d+(?:\.\d+)?\z/)

      expected == actual
    rescue ArgumentError
      expected == actual
    end

    def unknown?(value)
      UNKNOWN_VALUES.include?(value)
    end

    def check(name, passed, expected, actual, note: nil)
      result = { "name" => name, "passed" => !!passed, "expected" => expected, "actual" => actual }
      result["note"] = note if note
      result
    end
  end
end
