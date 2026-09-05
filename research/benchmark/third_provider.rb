# frozen_string_literal: true

# Independent third-provider validation. HeliosPay ground truth and behavioral
# vectors are authored in fixtures before this runner is executed.
require "bigdecimal"
require "fileutils"
require "json"
require "openssl"
require "tmpdir"
require "yaml"

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "provider_compiler"
require_relative "semantic_comparator"

module ThirdProviderBenchmark
  ROOT = File.expand_path("../..", __dir__)
  SPEC_PATH = File.join(ROOT, "fixtures", "heliospay_transfer_api.yaml")
  PROFILE_PATH = File.join(ROOT, "profiles", "heliospay_payments_v1.yml")
  EMPTY_DEFAULTS_PATH = File.join(ROOT, "fixtures", "empty_case_defaults.yml")
  RESOLVED_DEFAULTS_PATH = File.join(ROOT, "fixtures", "heliospay_case_defaults.yml")
  GROUND_TRUTH_PATH = File.join(ROOT, "fixtures", "heliospay_ground_truth.yml")
  VECTORS_PATH = File.join(ROOT, "fixtures", "heliospay_behavioral_vectors.yml")
  OUTPUT_PATH = ENV.fetch("THIRD_PROVIDER_OUTPUT", File.join(ROOT, "tmp", "benchmark", "third_provider.json"))

  module_function

  def run
    ground_truth = YAML.safe_load(File.read(GROUND_TRUTH_PATH, encoding: "UTF-8"), aliases: true)
    vectors = YAML.safe_load(File.read(VECTORS_PATH, encoding: "UTF-8"), aliases: true).fetch("vectors")
    spec_only = run_level("spec_only", EMPTY_DEFAULTS_PATH, ground_truth.fetch("resolution_levels").fetch("spec_only"), vectors, generate: false)
    resolved = run_level("resolved", RESOLVED_DEFAULTS_PATH, ground_truth.fetch("resolution_levels").fetch("resolved"), vectors, generate: true)
    report = {
      "schema_version" => 1,
      "benchmark" => "blind_third_provider",
      "provider" => ground_truth.fetch("provider"),
      "spec" => File.basename(SPEC_PATH),
      "ground_truth" => File.basename(GROUND_TRUTH_PATH),
      "behavioral_vectors" => File.basename(VECTORS_PATH),
      "ground_truth_authored_before_run" => true,
      "levels" => [spec_only, resolved],
      "aggregate" => {
        "levels_total" => 2,
        "levels_passed" => [spec_only, resolved].count { |item| item["passed"] },
        "spec_only" => spec_only,
        "resolved" => resolved,
        "critical_false_accept_count" => [spec_only, resolved].count { |item| item["critical_false_accept"] }
      }
    }
    FileUtils.mkdir_p(File.dirname(OUTPUT_PATH))
    File.write(OUTPUT_PATH, JSON.pretty_generate(report) + "\n", encoding: "UTF-8")
    puts JSON.pretty_generate(report.fetch("aggregate").slice("levels_total", "levels_passed", "critical_false_accept_count"))
    puts "Wrote #{OUTPUT_PATH}"
    report
  end

  def run_level(level, defaults_path, ground_truth, vectors, generate:)
    pipeline = ProviderCompiler::Pipeline.new(spec_path: SPEC_PATH, profile_path: PROFILE_PATH, defaults_path: defaults_path)
    generation = nil
    if generate
      output_dir = File.join(ROOT, "tmp", "benchmark", "heliospay-#{level}")
      FileUtils.rm_rf(output_dir)
      pipeline.validate_blueprint!
      ProviderCompiler::DeterministicGenerator.new.generate(pipeline.blueprint, pipeline.manifest, output_dir, examples: pipeline.defaults.examples, spec_document: pipeline.source_document.resolved)
      verification = ProviderCompiler::Verification.new.verify(output_dir)
      generation = { "status" => verification.fetch("passed") ? "passed" : "failed", "verification" => verification, "output_dir" => output_dir }
    end
    semantic_case = { "semantics" => ground_truth.fetch("semantic_subset"), "safety" => ground_truth.fetch("safety", {}) }
    validation = SemanticBenchmark::Comparator.new.compare(
      expected_decision: ground_truth.fetch("expected_decision"),
      expected_case: semantic_case,
      actual_decision: pipeline.blueprint.fetch("decision"),
      blueprint: pipeline.blueprint,
      generation: generation
    )
    behavioral = if generate && generation.fetch("status") == "passed"
                   run_behavioral_vectors(generation.fetch("output_dir"), vectors)
                 end
    passed = validation.fetch("passed") && (!behavioral || behavioral.fetch("passed"))
    {
      "level" => level,
      "expected_decision" => ground_truth.fetch("expected_decision"),
      "actual_decision" => pipeline.blueprint.fetch("decision"),
      "summary" => pipeline.manifest.to_h.fetch("summary"),
      "semantic_validation" => validation,
      "generation" => generation || { "status" => "not_attempted" },
      "behavioral_vectors" => behavioral,
      "passed" => passed,
      "critical_false_accept" => pipeline.blueprint.fetch("decision") == "ACCEPT" && (ground_truth.fetch("expected_decision") != "ACCEPT" || !validation.fetch("semantic_pass") || !validation.fetch("safety_pass") || behavioral&.fetch("passed") == false)
    }
  rescue ProviderCompiler::Error, ProviderCompiler::ValidationError, ProviderCompiler::BlueprintValidationError => e
    {
      "level" => level,
      "expected_decision" => ground_truth.fetch("expected_decision"),
      "actual_decision" => "COMPILER_ERROR",
      "error" => { "class" => e.class.name, "message" => e.message },
      "passed" => false,
      "critical_false_accept" => false
    }
  end

  def run_behavioral_vectors(output_dir, vectors)
    install_base_service
    class_name = "#{ProviderCompiler::Util.camel("HeliosPay")}Service"
    Provider.send(:remove_const, class_name) if Provider.const_defined?(class_name, false)
    load File.join(output_dir, "service.rb")
    service_class = Provider.const_get(class_name)
    rows = vectors.map do |name, vector|
      actual = execute_vector(service_class, vector)
      checks = compare_runtime(vector.fetch("expected"), actual, "behavioral.#{name}")
      { "name" => name, "passed" => checks.all? { |check| check["passed"] }, "expected" => vector.fetch("expected"), "actual" => json_safe(actual), "checks" => checks }
    rescue StandardError => e
      { "name" => name, "passed" => false, "expected" => vector.fetch("expected"), "actual" => { "error" => { "class" => e.class.name, "message" => e.message } }, "checks" => [] }
    end
    { "passed" => rows.all? { |row| row["passed"] }, "count" => rows.length, "passed_count" => rows.count { |row| row["passed"] }, "vectors" => rows }
  end

  def execute_vector(service_class, vector)
    credentials = vector.fetch("credentials")
    input = vector.fetch("input")
    case vector.fetch("kind")
    when "create_request"
      service_class.new(api_key: credentials.fetch("api_key")).build_create_request(input)
    when "fetch_status"
      response = vector.fetch("provider_response")
      client = Object.new
      client.define_singleton_method(:request) { |_method, _url, _headers, _body, _query| response }
      service_class.new(api_key: credentials.fetch("api_key"), client: client).fetch_status(input)
    when "webhook"
      secret = credentials.fetch("webhook_secret")
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), secret, input.fetch("raw_body"))
      service_class.new(api_key: "unused", webhook_secret: secret).process_callback(input.merge("signature" => signature))
    else
      raise ArgumentError, "unknown behavioral vector kind #{vector.fetch("kind")}"
    end
  end

  def install_base_service
    return if defined?(Provider::BaseService)

    Object.const_set(:Provider, Module.new) unless Object.const_defined?(:Provider)
    Provider.const_set(:BaseService, Class.new do
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

  def compare_runtime(expected, actual, path)
    expected.map do |key, value|
      observed = actual.is_a?(Hash) ? (actual[key] || actual[key.to_sym]) : nil
      if value.is_a?(Hash)
        compare_runtime(value, observed, "#{path}.#{key}")
      else
        [{ "name" => "#{path}.#{key}", "passed" => runtime_equal?(value, observed), "expected" => value, "actual" => json_safe(observed) }]
      end
    end.flatten
  end

  def runtime_equal?(expected, actual)
    return expected == actual unless expected.is_a?(Numeric) || actual.is_a?(Numeric)

    BigDecimal(expected.to_s) == BigDecimal(actual.to_s)
  rescue ArgumentError, TypeError
    expected.to_s == actual.to_s
  end

  def json_safe(value)
    case value
    when Hash then value.to_h { |key, item| [key.to_s, json_safe(item)] }
    when Array then value.map { |item| json_safe(item) }
    when BigDecimal then value.to_s("F")
    else value
    end
  end
end

if $PROGRAM_NAME == __FILE__
  report = ThirdProviderBenchmark.run
  exit 1 if report.dig("aggregate", "critical_false_accept_count").to_i.positive? || report.dig("aggregate", "levels_passed") != 2
end
