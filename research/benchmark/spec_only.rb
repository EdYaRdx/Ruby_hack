# frozen_string_literal: true

# Separate NovaPay spec-only benchmark lane. It intentionally loads empty
# provider defaults and compares the result to a hand-authored expectation file;
# it is not merged into the reference-case mutation score.
require "fileutils"
require "json"
require "tmpdir"
require "yaml"

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "provider_compiler"
require_relative "semantic_comparator"
require_relative "metrics"
require_relative "run"

module SpecOnlyBenchmark
  ROOT = File.expand_path("../..", __dir__)
  SOURCE_PATH = File.join(ROOT, "fixtures", "novapay_provider_api.yaml")
  PROFILE_PATH = File.join(ROOT, "profiles", "space_payments_v1.yml")
  EMPTY_DEFAULTS_PATH = File.join(ROOT, "fixtures", "empty_case_defaults.yml")
  CASES_PATH = File.join(__dir__, "spec_only_mutations.yml")
  OUTPUT_PATH = ENV.fetch("SPEC_ONLY_OUTPUT", File.join(ROOT, "research", "spec_only_novapay_report.json"))

  module_function

  def run
    source = YAML.safe_load(File.read(SOURCE_PATH, encoding: "UTF-8"), aliases: true)
    cases = YAML.safe_load(File.read(CASES_PATH, encoding: "UTF-8"), aliases: true).fetch("cases")
    run_id = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
    work_dir = File.join(ROOT, "tmp", "benchmark", "spec_only", run_id)
    FileUtils.mkdir_p(work_dir)

    results = cases.map do |id, expected|
      execute_case(id, expected, source, work_dir)
    end
    baseline = baseline_report
    aggregate = aggregate(results)
    report = {
      "schema_version" => 1,
      "benchmark" => "novapay_spec_only_mutations",
      "defaults" => "fixtures/empty_case_defaults.yml",
      "source" => "fixtures/novapay_provider_api.yaml",
      "ground_truth" => "research/benchmark/spec_only_mutations.yml",
      "methodology" => "hand-authored mutation -> empty-defaults pipeline -> independent semantic comparator",
      "baseline" => baseline,
      "cases" => results,
      "aggregate" => aggregate,
      "metrics" => {
        "baseline" => baseline.fetch("metrics"),
        "mutation_lane" => aggregate.fetch("metrics")
      }
    }
    FileUtils.mkdir_p(File.dirname(OUTPUT_PATH))
    File.write(OUTPUT_PATH, JSON.pretty_generate(report) + "\n", encoding: "UTF-8")
    puts JSON.pretty_generate(report.fetch("aggregate"))
    puts "Wrote #{OUTPUT_PATH}"
    report
  end

  def execute_case(id, expected, source, work_dir)
    document = Marshal.load(Marshal.dump(source))
    apply_mutation(document, expected.fetch("mutation"))
    case_dir = File.join(work_dir, id)
    FileUtils.mkdir_p(case_dir)
    spec_path = File.join(case_dir, "provider_api.yaml")
    File.write(spec_path, YAML.dump(document), encoding: "UTF-8")
    pipeline = ProviderCompiler::Pipeline.new(spec_path: spec_path, profile_path: PROFILE_PATH, defaults_path: EMPTY_DEFAULTS_PATH)
    blueprint = pipeline.blueprint
    actual_decision = blueprint.fetch("decision")
    summary = pipeline.manifest.to_h.fetch("summary")
    validation = SemanticBenchmark::Comparator.new.compare(
      expected_decision: expected.fetch("expected_decision"),
      expected_case: expected,
      actual_decision: actual_decision,
      blueprint: blueprint,
      generation: nil
    )
    {
      "case_id" => id,
      "mutation" => expected.fetch("mutation"),
      "expected_decision" => expected.fetch("expected_decision"),
      "actual_decision" => actual_decision,
      "summary" => summary,
      "metrics" => BenchmarkMetrics.from_manifest_summary(summary),
      "money_decision" => blueprint.dig("money", "decision"),
      "webhook_decision" => blueprint.dig("webhook", "decision"),
      "validation" => validation,
      "passed" => validation.fetch("passed")
    }
  rescue ProviderCompiler::Error, ProviderCompiler::ValidationError => e
    {
      "case_id" => id,
      "mutation" => expected.fetch("mutation"),
      "expected_decision" => expected.fetch("expected_decision"),
      "actual_decision" => "COMPILER_ERROR",
      "error" => e.message,
      "passed" => false
    }
  end

  def baseline_report
    pipeline = ProviderCompiler::Pipeline.new(spec_path: SOURCE_PATH, profile_path: PROFILE_PATH, defaults_path: EMPTY_DEFAULTS_PATH)
    summary = pipeline.manifest.to_h.fetch("summary")
    {
      "source" => "fixtures/novapay_provider_api.yaml",
      "profile" => "profiles/space_payments_v1.yml",
      "defaults" => "none",
      "decision" => pipeline.blueprint.fetch("decision"),
      "summary" => summary,
      "generation_attempted" => false,
      "metrics" => BenchmarkMetrics.from_manifest_summary(
        summary,
        total_specs: 1,
        fully_auto_ready_specs: 0,
        critical_false_accepts: 0,
        unsafe_generation_attempts: 0
      )
    }
  end

  def apply_mutation(document, mutation)
    case mutation
    when "baseline"
      nil
    when "explicit_scale"
      document.dig("components", "schemas", "CreatePayoutRequest", "properties", "amount")["x-minor-unit-scale"] = 100
    when "rename_amount"
      RealMutationBenchmark::Mutator.new(document).send(:rename_request_property, document, "amount", "sum")
    when "major_description"
      document.dig("components", "schemas", "CreatePayoutRequest", "properties", "amount")["description"] = "Amount in major RUB units"
    when "success_202"
      responses = document.dig("paths", "/payouts", "post", "responses")
      responses["202"] = responses.delete("201")
    when "missing_webhook_algorithm"
      operation = document.dig("paths", "/webhooks/payout", "post")
      operation["description"] = "Provider sends a signed notification."
      operation.fetch("parameters").first["description"] = "Signature of the request body"
    when "status_synonym"
      RealMutationBenchmark::Mutator.new(document).send(:replace_everywhere, document, "completed", "settled")
    else
      raise ArgumentError, "unknown spec-only mutation #{mutation}"
    end
  end

  def aggregate(results)
    total = results.length
    passed = results.count { |item| item["passed"] }
    actual = results.map { |item| item["actual_decision"] }
    critical_false_accepts = results.select do |item|
      item["expected_decision"] != "ACCEPT" && item["actual_decision"] == "ACCEPT"
    end
    total_decisions = results.sum { |item| item.dig("summary", "decisions").to_i }
    accepted_decisions = results.sum { |item| item.dig("summary", "accepted").to_i }
    review_required_decisions = results.sum { |item| item.dig("summary", "review_required").to_i }
    blocking_entries = results.sum { |item| item.dig("summary", "blocking").to_i }
    fully_auto_ready_specs = results.count do |item|
      item.dig("summary", "review_required").to_i.zero? && item.dig("summary", "blocking").to_i.zero?
    end
    metrics = BenchmarkMetrics.from_manifest_summary(
      {
        "decisions" => total_decisions,
        "accepted" => accepted_decisions,
        "review_required" => review_required_decisions,
        "blocking" => blocking_entries
      },
      total_specs: total,
      fully_auto_ready_specs: fully_auto_ready_specs,
      critical_false_accepts: critical_false_accepts.length,
      unsafe_generation_attempts: 0
    )
    {
      "cases_total" => total,
      "cases_passed" => passed,
      "cases_failed" => total - passed,
      "decision_accuracy" => percentage(results.count { |item| item.dig("validation", "decision_pass") }, total),
      "safe_decision_coverage" => percentage(passed, total),
      "automatic_accept_rate" => percentage(actual.count { |decision| decision == "ACCEPT" }, total),
      "accept_count" => actual.count { |decision| decision == "ACCEPT" },
      "review_required_count" => actual.count { |decision| decision == "REVIEW_REQUIRED" },
      "unknown_count" => actual.count { |decision| decision == "UNKNOWN" },
      "blocking_count" => results.sum { |item| item.dig("summary", "blocking").to_i },
      "review_required_rate" => percentage(actual.count { |decision| decision == "REVIEW_REQUIRED" }, total),
      "unknown_rate" => percentage(actual.count { |decision| decision == "UNKNOWN" }, total),
      "semantic_accept_accuracy" => percentage(results.count { |item| item.dig("validation", "semantic_pass") && item["expected_decision"] == "ACCEPT" }, results.count { |item| item["expected_decision"] == "ACCEPT" }),
      "critical_false_accept_count" => critical_false_accepts.length,
      "critical_false_accept_cases" => critical_false_accepts.map { |item| item.fetch("case_id") },
      "metrics" => metrics,
      "formula" => {
        "automatic_accept_rate" => "ACCEPT decisions / total cases",
        "safe_decision_coverage" => "independently passed cases / total cases",
        "decision_accuracy" => "decision comparator passes / total cases",
        "critical_false_accepts" => "ACCEPT where hand-authored expected decision is not ACCEPT"
      }
    }
  end

  def percentage(numerator, denominator)
    return nil if denominator.zero?

    (100.0 * numerator / denominator).round(1)
  end
end

SpecOnlyBenchmark.run if $PROGRAM_NAME == __FILE__
