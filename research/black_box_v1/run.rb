# frozen_string_literal: true

# Black-box corpus runner. It invokes the public CLI in a subprocess and only
# inspects emitted artifacts, diagnostics, and verification results. It does
# not call analyzers or copy their policy into the expected answers.

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "yaml"

ROOT = File.expand_path(ENV.fetch("BLACK_BOX_ROOT", File.expand_path("../..", __dir__)))
CORPUS = File.join(__dir__)
OUTPUT = ENV.fetch("BLACK_BOX_OUTPUT", File.join(ROOT, "research", "black_box_v1", "baseline_results.json"))
PROFILE = File.join(ROOT, "profiles", "space_payments_v1.yml")
DEFAULTS = File.join(ROOT, "fixtures", "empty_case_defaults.yml")
CLI = File.join(ROOT, "bin", "provider_compiler")

def absolute(path)
  File.expand_path(path, CORPUS)
end

def run_command(*args)
  stdout, stderr, status = Open3.capture3(RbConfig.ruby, *args, chdir: ROOT)
  { "exit_status" => status.exitstatus, "stdout" => stdout, "stderr" => stderr }
end

def equivalent?(expected, actual)
  expected == actual || (expected.nil? && actual.nil?)
end

def check(name, expected, actual)
  { "name" => name, "passed" => equivalent?(expected, actual), "expected" => expected, "actual" => actual }
end

def operation_checks(expected, blueprint)
  expected.fetch("operation", {}).flat_map do |role, subset|
    actual = Array(blueprint["operations"]).find { |item| item["canonical"] == role }
    actual ||= Array(blueprint["endpoints"]).find { |item| item["canonical"] == role }
    if actual
      subset.map { |key, value| check("operation.#{role}.#{key}", value, actual[key]) }
    else
      [check("operation.#{role}", "present", nil)]
    end
  end
end

def auth_checks(expected, blueprint)
  subset = expected.fetch("auth", {})
  return [] if subset.empty?

  strategy = blueprint.dig("auth", "strategy") || {}
  subset.map do |key, value|
    actual = case key
             when "kind", "transport", "name", "scheme" then strategy[key]
             when "scheme_type"
               selected = Array(blueprint.dig("auth", "schemes")).find { |item| item["name"] == blueprint.dig("auth", "selected") } || Array(blueprint.dig("auth", "schemes")).first
               selected && selected["type"]
             when "unsupported" then strategy.empty? || blueprint.dig("auth", "selected").nil?
             else blueprint.dig("auth", key)
             end
    check("auth.#{key}", value, actual)
  end
end

def money_checks(expected, blueprint)
  expected.fetch("money", {}).flat_map do |area, subset|
    next [] if area == "unresolved"
    actual = blueprint.dig("money", area) || (area == "request_conversion" ? blueprint["money"]["request_conversion"] : nil)
    subset.map do |key, value|
      observed = if area == "provider" && key == "request_field"
                   actual && actual["field"]
                 else
                   actual && actual[key]
                 end
      check("money.#{area}.#{key}", value, observed)
    end
  end
end

def webhook_checks(expected, blueprint)
  subset = expected.fetch("webhook", {})
  return [] if subset.empty?

  webhook = blueprint["webhook"] || {}
  signature = webhook["signature"] || {}
  subset.reject { |key, _value| key == "contradiction_vector" }.map do |key, value|
    actual = case key
             when "endpoint", "mode" then webhook[key]
             when "algorithm", "header", "input", "encoding"
               signature[key]
             else
               webhook[key]
             end
    check("webhook.#{key}", value, actual)
  end
end

def extra_checks(expected, blueprint)
  Array(expected["extra_operations"]).map do |subset|
    actual = Array(blueprint["extra_operations"]).find { |item| item["operation_id"] == subset["operation_id"] || item["path"] == subset["path"] }
    if actual
      subset.map { |key, value| check("extra_operations.#{subset["operation_id"]}.#{key}", value, actual[key]) }
    else
      [check("extra_operations.#{subset["operation_id"]}", "present", nil)]
    end
  end.flatten
end

def parameter_checks(expected, blueprint)
  semantic = expected.fetch("semantic", {})
  actual = Array(blueprint["unsupported_features"])
  checks = []
  Array(semantic["required_parameters"]).each do |subset|
    item = actual.find { |candidate| candidate["name"] == subset["name"] && candidate["in"] == subset["in"] }
    checks << check("required_parameters.#{subset["in"]}.#{subset["name"]}", subset["generation_impact"], item && item["generation_impact"])
  end
  Array(semantic["optional_parameters"]).each do |subset|
    item = actual.find { |candidate| candidate["name"] == subset["name"] && candidate["in"] == subset["in"] }
    checks << check("optional_parameters.#{subset["in"]}.#{subset["name"]}", true, !item.nil?)
  end
  checks
end

def unsupported_checks(expected, blueprint)
  actual = Array(blueprint["unsupported_features"])
  Array(expected.dig("semantic", "unsupported")).reject { |subset| subset["feature"] == "missing_operation_id" }.map do |subset|
    item = actual.find { |candidate| candidate["feature"] == subset["feature"] }
    check("unsupported.#{subset["feature"]}", subset["severity"], item && item["severity"])
  end
end

def semantic_checks(case_truth, blueprint)
  return [{ "name" => "blueprint", "passed" => false, "expected" => "present", "actual" => nil }] unless blueprint

  [
    operation_checks(case_truth.fetch("semantic", {}), blueprint),
    auth_checks(case_truth.fetch("semantic", {}), blueprint),
    money_checks(case_truth.fetch("semantic", {}), blueprint),
    webhook_checks(case_truth.fetch("semantic", {}), blueprint),
    extra_checks(case_truth.fetch("semantic", {}), blueprint),
    parameter_checks(case_truth, blueprint),
    unsupported_checks(case_truth, blueprint)
  ].flatten
end

def safety_checks(case_truth, blueprint, actual_decision)
  expected = case_truth.fetch("expected_decision")
  checks = [check("decision", expected, actual_decision)]
  if expected == "UNKNOWN"
    checks << check("unknown.preserved", true, blueprint && (!Array(blueprint["unknowns"]).empty? || Array(blueprint["decisions"]).any? { |item| item["outcome"] == "UNKNOWN" }))
  elsif expected == "REVIEW_REQUIRED"
    checks << check("review.decision", "REVIEW_REQUIRED", actual_decision)
  end
  Array(case_truth.dig("semantic", "safety", "forbid_resolved")).each do |path|
    value = path.split(".").reduce(blueprint) { |current, key| current.is_a?(Hash) ? current[key] : nil }
    safe = value.nil? || value == "UNKNOWN" || (value.is_a?(Hash) && value["status"] != "resolved")
    checks << check("safety.forbid_resolved.#{path}", true, safe)
  end
  checks
end

def execute_case(case_truth, root)
  id = case_truth.fetch("id")
  case_dir = File.join(root, id)
  FileUtils.mkdir_p(case_dir)
  out_dir = File.join(case_dir, "analyzed")
  command = run_command(
    CLI, "analyze",
    "--spec", absolute(case_truth.fetch("spec")),
    "--profile", PROFILE,
    "--defaults", DEFAULTS,
    "--out", out_dir
  )
  blueprint_path = File.join(out_dir, "provider_blueprint.json")
  manifest_path = File.join(out_dir, "review_manifest.json")
  blueprint = File.file?(blueprint_path) ? JSON.parse(File.read(blueprint_path, encoding: "UTF-8")) : nil
  manifest = File.file?(manifest_path) ? JSON.parse(File.read(manifest_path, encoding: "UTF-8")) : nil
  actual_decision = blueprint && blueprint["decision"] || "COMPILER_ERROR"
  generation = { "status" => "not_attempted" }
  if actual_decision == "ACCEPT"
    generated = run_command(CLI, "generate", "--spec", absolute(case_truth.fetch("spec")), "--profile", PROFILE, "--defaults", DEFAULTS, "--out", File.join(case_dir, "generated"))
    generation = { "status" => generated["exit_status"].zero? ? "passed" : "failed", "stderr" => generated["stderr"].strip }
  end
  semantic = semantic_checks(case_truth, blueprint)
  safety = safety_checks(case_truth, blueprint, actual_decision)
  passed = semantic.all? { |item| item["passed"] } && safety.all? { |item| item["passed"] }
  {
    "case_id" => id,
    "expected_decision" => case_truth.fetch("expected_decision"),
    "actual_decision" => actual_decision,
    "generation" => generation,
    "manifest_summary" => manifest && manifest["summary"],
    "semantic_checks" => semantic,
    "safety_checks" => safety,
    "passed" => passed,
    "compiler" => command.slice("exit_status", "stdout", "stderr"),
    "failure_class" => passed ? nil : (actual_decision == "COMPILER_ERROR" ? "compiler_crash_or_error" : "semantic_or_decision_mismatch")
  }
end

truth = YAML.safe_load(File.read(File.join(CORPUS, "ground_truth.yml"), encoding: "UTF-8"), aliases: true).fetch("cases")
run_root = File.join(ROOT, "tmp", "black_box_v1", "baseline")
FileUtils.mkdir_p(run_root)
results = truth.map { |case_truth| execute_case(case_truth, run_root) }
total = results.length
actual = results.map { |item| item["actual_decision"] }
report = {
  "schema_version" => 1,
  "corpus" => "research/black_box_v1",
  "cases" => results,
  "aggregate" => {
    "cases_total" => total,
    "cases_passed" => results.count { |item| item["passed"] },
    "decision_automation_rate" => (actual.count { |value| value == "ACCEPT" }.fdiv(total) * 100).round(1),
    "review_rate" => (actual.count { |value| value == "REVIEW_REQUIRED" }.fdiv(total) * 100).round(1),
    "unknown_rate" => (actual.count { |value| value == "UNKNOWN" }.fdiv(total) * 100).round(1),
    "safe_semantic_accuracy" => (results.count { |item| item["passed"] }.fdiv(total) * 100).round(1),
    "fully_auto_ready_rate" => (results.count { |item| item["actual_decision"] == "ACCEPT" && item.dig("generation", "status") == "passed" }.fdiv(total) * 100).round(1),
    "generation_success_rate" => begin
      attempted = results.select { |item| item.dig("generation", "status") != "not_attempted" }
      attempted.empty? ? 0.0 : (attempted.count { |item| item.dig("generation", "status") == "passed" }.fdiv(attempted.length) * 100).round(1)
    end,
    "runtime_vector_rate" => 0.0,
    "critical_false_accept_count" => results.count { |item| item["actual_decision"] == "ACCEPT" && item["expected_decision"] != "ACCEPT" },
    "unsafe_generation_attempt_count" => results.count { |item| item["actual_decision"] == "ACCEPT" && item["expected_decision"] != "ACCEPT" },
    "compiler_crash_count" => results.count { |item| item["actual_decision"] == "COMPILER_ERROR" }
  }
}
File.write(OUTPUT, JSON.pretty_generate(report) + "\n", encoding: "UTF-8")
failures_path = ENV.fetch("BLACK_BOX_FAILURES", File.join(File.dirname(OUTPUT), "failures.json"))
failures = report.fetch("cases").reject { |item| item["passed"] }
File.write(failures_path, JSON.pretty_generate("schema_version" => 1, "source" => OUTPUT, "failures" => failures) + "\n", encoding: "UTF-8")
puts JSON.pretty_generate(report.fetch("aggregate"))
puts "Wrote #{OUTPUT}"
