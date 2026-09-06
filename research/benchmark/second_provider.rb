# frozen_string_literal: true

# Independent-provider validation. Ground truth is loaded from the hand-authored
# aurora_ground_truth.yml and is never derived from a compiler result.

require "fileutils"
require "bigdecimal"
require "json"
require "openssl"
require "yaml"

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "provider_compiler"
require_relative "semantic_comparator"
require_relative "metrics"

module SecondProviderBenchmark
  ROOT = File.expand_path("../..", __dir__)
  SPEC_PATH = File.join(ROOT, "fixtures", "aurora_transfer_api.yaml")
  PROFILE_PATH = File.join(ROOT, "profiles", "aurora_payments_v1.yml")
  EMPTY_DEFAULTS_PATH = File.join(ROOT, "fixtures", "empty_case_defaults.yml")
  RESOLVED_DEFAULTS_PATH = File.join(ROOT, "fixtures", "aurora_case_defaults.yml")
  GROUND_TRUTH_PATH = File.join(ROOT, "fixtures", "aurora_ground_truth.yml")
  BEHAVIORAL_VECTORS_PATH = File.join(ROOT, "fixtures", "aurora_behavioral_vectors.yml")
  OUTPUT_PATH = ENV.fetch("SECOND_PROVIDER_OUTPUT", File.join(ROOT, "tmp", "benchmark", "second_provider.json"))

  module_function

  def run
    ground_truth = YAML.safe_load(File.read(GROUND_TRUTH_PATH, encoding: "UTF-8"), aliases: true)
    behavioral_vectors = YAML.safe_load(File.read(BEHAVIORAL_VECTORS_PATH, encoding: "UTF-8"), aliases: true).fetch("vectors", {})
    cases = [
      run_level("pure_generic", EMPTY_DEFAULTS_PATH, ground_truth, behavioral_vectors),
      # Safe reusable rules are provider-neutral built-in rules in the current
      # compiler. Keep this level explicit so that no provider-specific rule
      # layer is implied by the report.
      run_level("generic_plus_safe_reusable_rules", EMPTY_DEFAULTS_PATH, ground_truth, behavioral_vectors),
      run_level("generic_plus_case_defaults", RESOLVED_DEFAULTS_PATH, ground_truth, behavioral_vectors)
    ]
    defaults = YAML.safe_load(File.read(RESOLVED_DEFAULTS_PATH, encoding: "UTF-8"), aliases: true)
    report = {
      "schema_version" => 1,
      "benchmark" => "independent_second_provider",
      "provider" => ground_truth.fetch("provider"),
      "spec" => File.basename(SPEC_PATH),
      "ground_truth" => File.basename(GROUND_TRUTH_PATH),
      "behavioral_vectors" => File.basename(BEHAVIORAL_VECTORS_PATH),
      "methodology" => "hand-authored OpenAPI + hand-authored ground truth -> real compiler at pure-generic, safe-reusable-rule and resolved levels",
      "cases" => cases,
      "provider_specific_resolution_cost" => {
        "defaults_file" => File.basename(RESOLVED_DEFAULTS_PATH),
        "nonempty_sections" => defaults.select { |_key, value| value.is_a?(Hash) || value.is_a?(Array) }.keys,
        "override_sections" => %w[money statuses webhook field_mappings]
      },
      "aggregate" => {
        "levels_total" => cases.length,
        "levels_passed" => cases.count { |item| item["passed"] },
        "pure_generic" => cases.find { |item| item["level"] == "pure_generic" }.fetch("actual"),
        "safe_reusable_rules" => cases.find { |item| item["level"] == "generic_plus_safe_reusable_rules" }.fetch("actual"),
        "resolved" => cases.find { |item| item["level"] == "generic_plus_case_defaults" }.fetch("actual"),
        "critical_false_accept_count" => cases.count { |item| item["critical_false_accept"] },
        "decision_accuracy" => percentage(cases.count { |item| item.dig("actual", "semantic_validation", "decision_pass") }, cases.length),
        "semantic_accuracy" => percentage(cases.count { |item| item.dig("actual", "semantic_validation", "semantic_pass") }, cases.length),
        "safe_decision_coverage" => percentage(cases.count { |item| item["passed"] }, cases.length),
        "behavioral_vector_pass_rate" => behavioral_vector_pass_rate(cases),
        "metrics" => {
          "levels" => cases.to_h { |item| [item.fetch("level"), item.fetch("actual").fetch("metrics")] },
          "formulas" => {
            "decision_automation_rate" => "accepted_decisions / total_decisions per level",
            "review_rate" => "review_required_decisions / total_decisions per level",
            "fully_auto_ready_rate" => "specs_with_zero_review_and_zero_blocking / total_specs per level",
            "critical_false_accepts" => "unsafe ACCEPTs for hand-authored critical cases",
            "unsafe_generation_attempts" => "generation attempts while a critical decision is unresolved"
          }
        }
      }
    }
    FileUtils.mkdir_p(File.dirname(OUTPUT_PATH))
    ProviderCompiler::Util.write_text(OUTPUT_PATH, ProviderCompiler::Util.pretty_json(report) + "\n")
    puts ProviderCompiler::Util.pretty_json(report.fetch("aggregate"))
    puts "Wrote #{OUTPUT_PATH}"
    report
  end

  def run_level(level, defaults_path, ground_truth, behavioral_vectors)
    level_ground_truth = ground_truth.fetch("resolution_levels").fetch(level)
    expected = level_ground_truth.fetch("expected_decision")
    semantic_case = {
      "semantics" => level_ground_truth.fetch("semantic_subset", {}),
      "safety" => level_ground_truth.fetch("safety", {})
    }
    pipeline = ProviderCompiler::Pipeline.new(spec_path: SPEC_PATH, profile_path: PROFILE_PATH, defaults_path: defaults_path)
    blueprint = pipeline.blueprint
    summary = pipeline.manifest.to_h.fetch("summary")
    actual = {
      "decision" => blueprint.fetch("decision"),
      "operations" => blueprint.fetch("operations").map { |item| item.slice("operation_id", "canonical", "method", "path") },
      "extra_operations" => blueprint.fetch("extra_operations").map { |item| item.slice("operation_id", "kind", "path", "blocking", "preserved") },
      "auth" => blueprint.fetch("auth"),
      "money" => blueprint.fetch("money"),
      "statuses" => blueprint.fetch("statuses"),
      "webhook" => blueprint.fetch("webhook"),
      "idempotency" => blueprint.fetch("idempotency"),
      "manifest" => summary
    }
    actual["generation"] = generation_status(pipeline, blueprint, defaults_path, level)
    semantic_validation = SemanticBenchmark::Comparator.new.compare(
      expected_decision: expected,
      expected_case: semantic_case,
      actual_decision: blueprint.fetch("decision"),
      blueprint: blueprint,
      generation: actual["generation"]
    )
    actual["semantic_validation"] = semantic_validation
    if level == "generic_plus_case_defaults" && actual.dig("generation", "status") == "passed"
      actual["behavioral_vectors"] = run_behavioral_vectors(actual.dig("generation", "output_dir"), behavioral_vectors)
    end
    passed = semantic_validation.fetch("passed") && (!actual.key?("behavioral_vectors") || actual.fetch("behavioral_vectors").fetch("passed"))
    critical_false_accept = actual.fetch("decision") == "ACCEPT" && (expected != "ACCEPT" || !semantic_validation.fetch("semantic_pass") || !semantic_validation.fetch("safety_pass") || actual.dig("behavioral_vectors", "passed") == false)
    unsafe_generation_attempts = actual.dig("generation", "status") != "not_attempted" && expected != "ACCEPT" ? 1 : 0
    actual["metrics"] = BenchmarkMetrics.from_manifest_summary(
      summary,
      total_specs: 1,
      fully_auto_ready_specs: actual.fetch("decision") == "ACCEPT" && summary.fetch("review_required").zero? && summary.fetch("blocking").zero? ? 1 : 0,
      critical_false_accepts: critical_false_accept ? 1 : 0,
      unsafe_generation_attempts: unsafe_generation_attempts
    )
    {
      "level" => level,
      "expected" => { "decision" => expected },
      "actual" => actual,
      "passed" => passed,
      "critical_false_accept" => critical_false_accept
    }
  rescue ProviderCompiler::Error, ProviderCompiler::ValidationError, Psych::Exception, Errno::ENOENT => e
    {
      "level" => level,
      "expected" => { "decision" => expected },
      "actual" => { "decision" => "UNKNOWN", "error" => { "class" => e.class.name, "message" => e.message } },
      "passed" => expected == "UNKNOWN",
      "critical_false_accept" => false
    }
  end

  def generation_status(pipeline, blueprint, defaults_path, level)
    return { "status" => "not_attempted", "reason" => blueprint.fetch("decision") } unless blueprint.fetch("decision") == "ACCEPT" || level == "generic_plus_case_defaults"

    begin
      profile = ProviderCompiler::BaseServiceProfile.load(PROFILE_PATH)
      pipeline.validate_blueprint!
      output_dir = File.join(ROOT, "tmp", "benchmark", "aurora-#{level}")
      examples = ProviderCompiler::CaseDefaults.load(defaults_path).examples
      ProviderCompiler::DeterministicGenerator.new.generate(blueprint, pipeline.manifest, output_dir, examples: examples, spec_document: pipeline.source_document.resolved)
      verification = ProviderCompiler::Verification.new.verify(output_dir)
      { "status" => verification.fetch("passed") ? "passed" : "failed", "production_ready" => blueprint.fetch("decision") == "ACCEPT", "verification" => verification, "profile_loaded" => !profile.nil?, "output_dir" => output_dir }
    rescue ProviderCompiler::Error, ProviderCompiler::ValidationError, Errno::ENOENT => e
      { "status" => "failed", "error" => { "class" => e.class.name, "message" => e.message } }
    end
  end

  def run_behavioral_vectors(output_dir, vectors)
    load_base_service_stub
    load File.join(output_dir, "service.rb")
    service_class = Provider.const_get("AuroraService")
    results = vectors.map do |name, vector|
      actual = execute_behavioral_vector(service_class, vector)
      checks = compare_runtime_subset(vector.fetch("expected"), actual, "behavioral.#{name}")
      { "name" => name, "passed" => checks.all? { |item| item["passed"] }, "expected" => vector.fetch("expected"), "actual" => json_safe(actual), "checks" => checks }
    rescue StandardError => e
      { "name" => name, "passed" => false, "expected" => vector.fetch("expected"), "actual" => { "error" => { "class" => e.class.name, "message" => e.message } }, "checks" => [{ "name" => "behavioral.#{name}", "passed" => false, "expected" => vector.fetch("expected"), "actual" => nil, "note" => e.message }] }
    end
    { "passed" => results.all? { |item| item["passed"] }, "vector_count" => results.length, "vectors" => results }
  end

  def execute_behavioral_vector(service_class, vector)
    credentials = vector.fetch("credentials", {})
    input = vector.fetch("input", {})
    service = case vector.fetch("kind")
              when "create_request"
                service_class.new(api_key: credentials.fetch("api_key"))
              when "fetch_status"
                client = Object.new
                response = vector.fetch("provider_response")
                client.define_singleton_method(:request) { |_method, _url, _headers, _body, _query| response }
                service_class.new(api_key: credentials.fetch("api_key"), client: client)
              when "webhook"
                service_class.new(api_key: "unused", webhook_secret: credentials.fetch("webhook_secret"))
              else
                raise ArgumentError, "unknown behavioral vector kind #{vector.fetch("kind")}"
              end
    case vector.fetch("kind")
    when "create_request"
      service.build_create_request(input)
    when "fetch_status"
      service.fetch_status(input)
    when "webhook"
      raw_body = input.fetch("raw_body")
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), credentials.fetch("webhook_secret"), raw_body)
      service.process_callback(input.merge("signature" => signature))
    end
  end

  def load_base_service_stub
    return if defined?(Provider::BaseService)

    module_provider = if Object.const_defined?(:Provider)
                        Provider
                      else
                        Object.const_set(:Provider, Module.new)
                      end
    module_provider.const_set(:BaseService, Class.new do
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
    end)
  end

  def compare_runtime_subset(expected, actual, path)
    return [runtime_check(path, false, expected, nil, "actual runtime result is absent")] unless actual.is_a?(Hash)

    expected.flat_map do |key, value|
      observed = actual[key] || actual[key.to_sym]
      if value.is_a?(Hash)
        compare_runtime_subset(value, observed, "#{path}.#{key}")
      else
        [runtime_check("#{path}.#{key}", runtime_equivalent?(value, observed), value, observed)]
      end
    end
  end

  def runtime_check(name, passed, expected, actual, note = nil)
    result = { "name" => name, "passed" => !!passed, "expected" => expected, "actual" => json_safe(actual) }
    result["note"] = note if note
    result
  end

  def runtime_equivalent?(expected, actual)
    return expected == actual unless expected.is_a?(String) && (actual.is_a?(Numeric) || actual.is_a?(BigDecimal))

    BigDecimal(expected) == BigDecimal(actual.to_s)
  rescue ArgumentError
    expected == actual
  end

  def json_safe(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, item), result| result[key.to_s] = json_safe(item) }
    when Array
      value.map { |item| json_safe(item) }
    when BigDecimal
      value.to_s("F")
    else
      value
    end
  end

  def behavioral_vector_pass_rate(cases)
    resolved = cases.find { |item| item["level"] == "generic_plus_case_defaults" }
    vectors = resolved && resolved.dig("actual", "behavioral_vectors")
    vectors ? percentage(vectors.fetch("vectors").count { |item| item["passed"] }, vectors.fetch("vectors").length) : nil
  end

  def percentage(numerator, denominator)
    return nil if denominator.zero?

    (100.0 * numerator / denominator).round(1)
  end
end

if $PROGRAM_NAME == __FILE__
  report = SecondProviderBenchmark.run
  exit 1 if report.dig("aggregate", "critical_false_accept_count").to_i.positive?
end
