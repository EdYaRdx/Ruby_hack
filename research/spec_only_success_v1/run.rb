#!/usr/bin/env ruby
# frozen_string_literal: true

# Independent spec-only success corpus. The comparator below intentionally
# reads hand-authored ground truth and runtime vectors directly; it never
# derives expectations from a Blueprint or from generated fixtures.
require "fileutils"
require "json"
require "openssl"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
CORPUS_ROOT = __dir__
GROUND_TRUTH_PATH = File.join(CORPUS_ROOT, "ground_truth.yml")
VECTORS_PATH = File.join(CORPUS_ROOT, "behavioral_vectors.yml")
OUTPUT_PATH = File.join(CORPUS_ROOT, "results.json")
WORK_ROOT = File.join(ROOT, "tmp", "spec_only_success_v1")
PROFILE_PATH = File.join(ROOT, "profiles", "space_payments_v1.yml")
EMPTY_DEFAULTS_PATH = File.join(ROOT, "fixtures", "empty_case_defaults.yml")

$LOAD_PATH.unshift(File.join(ROOT, "lib"))
require "provider_compiler"

module Provider
  class BaseService
    def check_conditions(_operation, _request_method)
      success
    end

    def success(result: nil)
      { "ok" => true, "result" => result }
    end

    def failure(code, i18n_key)
      { "ok" => false, "failure_code" => code, "i18n_key" => i18n_key }
    end

    def approve_operation(operation)
      { "ok" => true, "action" => "approve_operation", "operation" => operation }
    end

    def reject_operation(operation)
      { "ok" => true, "action" => "reject_operation", "operation" => operation }
    end
  end
end

class StaticClient
  def initialize(response)
    @response = response
  end

  def request(_method, _url, _headers, _body, _query)
    { "http_status" => 200, "body" => @response }
  end
end

module SpecOnlySuccessV1
  module_function

  def run
    truth = YAML.safe_load(File.read(GROUND_TRUTH_PATH, encoding: "UTF-8"), aliases: false)
    vectors = YAML.safe_load(File.read(VECTORS_PATH, encoding: "UTF-8"), aliases: false).fetch("vectors")
    FileUtils.rm_rf(WORK_ROOT)
    FileUtils.mkdir_p(WORK_ROOT)

    provider_results = truth.fetch("providers").map do |provider_id, expected|
      execute(provider_id, expected, vectors.fetch(provider_id))
    end
    aggregate = aggregate(provider_results)
    report = {
      "schema_version" => 1,
      "benchmark" => "spec_only_success_v1",
      "methodology" => "three materially different explicit OpenAPI specs; hand-authored semantics and behavioral vectors; no CaseDefaults or HUMAN_CONFIRMED overrides",
      "providers" => provider_results,
      "aggregate" => aggregate,
      "formulas" => {
        "spec_only_accept_rate" => "spec-only ACCEPT providers / total providers",
        "generation_pass_rate" => "providers with generated service, contract smoke and verification PASS / total providers",
        "behavioral_vector_pass_rate" => "providers with all independent runtime vectors PASS / total providers",
        "corpus_pass" => "all providers pass decision, semantic, generation and behavioral checks"
      }
    }
    ProviderCompiler::Util.write_text(OUTPUT_PATH, ProviderCompiler::Util.pretty_json(report) + "\n")
    puts ProviderCompiler::Util.pretty_json(aggregate)
    puts "Wrote #{OUTPUT_PATH}"
    abort "spec-only success corpus failed" unless aggregate.fetch("corpus_pass")

    report
  end

  def execute(provider_id, expected, provider_vectors)
    spec_path = File.join(CORPUS_ROOT, expected.fetch("spec"))
    pipeline = ProviderCompiler::Pipeline.new(
      spec_path: spec_path,
      profile_path: PROFILE_PATH,
      defaults_path: EMPTY_DEFAULTS_PATH
    )
    blueprint = pipeline.blueprint
    semantic = SemanticComparator.new(expected, blueprint).compare
    decision_pass = blueprint.fetch("decision") == expected.fetch("expected_decision")
    no_defaults = pipeline.defaults.data.empty? && pipeline.review_override.nil? && !contains_value?(blueprint, "CASE_DEFAULT") && !contains_value?(blueprint, "HUMAN_CONFIRMED")
    generation = { "attempted" => false, "passed" => false, "verification" => nil }
    vectors = []

    if decision_pass && semantic.fetch("passed") && expected.fetch("expected_decision") == "ACCEPT"
      output_dir = File.join(WORK_ROOT, provider_id)
      ProviderCompiler::DeterministicGenerator.new.generate(
        blueprint,
        pipeline.manifest,
        output_dir,
        examples: pipeline.defaults.examples,
        spec_document: pipeline.source_document.resolved
      )
      pipeline.validate_blueprint!
      verification = ProviderCompiler::Verification.new.verify(output_dir)
      verification.fetch("syntax", []).each { |entry| entry["path"] = File.basename(entry.fetch("path")) }
      generation = {
        "attempted" => true,
        "passed" => verification.fetch("passed") == true,
        "verification" => verification
      }
      vectors = run_vectors(output_dir, provider_vectors)
    end

    runtime_pass = vectors.all? { |item| item.fetch("passed") }
    {
      "provider_id" => provider_id,
      "spec" => expected.fetch("spec"),
      "expected_decision" => expected.fetch("expected_decision"),
      "actual_decision" => blueprint.fetch("decision"),
      "decision_pass" => decision_pass,
      "semantic" => semantic,
      "generation" => generation,
      "behavioral_vectors" => vectors,
      "no_case_defaults_or_human_overrides" => no_defaults,
      "passed" => decision_pass && semantic.fetch("passed") && generation.fetch("passed") && runtime_pass && no_defaults,
      "manifest_summary" => pipeline.manifest.to_h.fetch("summary")
    }
  rescue ProviderCompiler::Error, ProviderCompiler::ValidationError, ProviderCompiler::BlueprintValidationError => e
    {
      "provider_id" => provider_id,
      "spec" => expected.fetch("spec"),
      "expected_decision" => expected.fetch("expected_decision"),
      "actual_decision" => "COMPILER_ERROR",
      "error" => "#{e.class}: #{e.message}",
      "decision_pass" => false,
      "semantic" => { "passed" => false, "failures" => ["compiler error"] },
      "generation" => { "attempted" => false, "passed" => false },
      "behavioral_vectors" => [],
      "no_case_defaults_or_human_overrides" => false,
      "passed" => false
    }
  end

  def run_vectors(output_dir, provider_vectors)
    service_class = load_service(File.join(output_dir, "service.rb"))
    service = service_class.new(api_key: "independent-vector-key", webhook_secret: "independent-vector-secret")
    provider_vectors.map do |name, vector|
      result = case name
               when "create_request"
                 compare_request(service.build_create_request(vector.fetch("input"), vector.fetch("request_method", "sbp")), vector.fetch("expected"), service_class)
               when "fetch_status"
                 compare_request(service.fetch_status(vector.fetch("input")), vector.fetch("expected"), service_class)
               when "provider_status_response"
                 response = StaticClient.new(vector.fetch("response"))
                 status_service = service_class.new(api_key: "independent-vector-key", client: response)
                 actual = status_service.fetch_status(vector.fetch("input"))
                 compare_result(actual, vector.fetch("expected"))
               when "settled_webhook", "declined_webhook"
                 raw_body = JSON.generate(vector.fetch("input"))
                 signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "independent-vector-secret", raw_body)
                 actual = service.process_callback(raw_body: raw_body, signature: signature, parsed_payload: vector.fetch("input"))
                 compare_callback(actual, vector.fetch("expected"))
               when "polling_callback"
                 actual = service.process_callback(vector.fetch("input"))
                 { "passed" => actual["error_code"].to_s == vector.dig("expected", "error_code").to_s, "actual" => actual, "expected" => vector.fetch("expected") }
               else
                 { "passed" => false, "error" => "unknown vector #{name}" }
               end
      result.merge("name" => name)
    rescue StandardError => e
      { "name" => name, "passed" => false, "error" => "#{e.class}: #{e.message}" }
    end
  end

  def compare_request(actual, expected, service_class)
    checks = {
      "method" => actual["method"] == expected.fetch("method"),
      "path" => actual["path"] == expected.fetch("path"),
      "body" => expected.key?("body") ? actual["body"] == expected["body"] : true
    }
    if expected.key?("query")
      checks["query"] = expected.fetch("query").all? do |key, expected_value|
        actual_value = actual.fetch("query", {})[key.to_s]
        expected_value == "[REDACTED]" ? !actual_value.to_s.empty? : actual_value == expected_value
      end
    end
    strategy = service_class.const_get(:AUTH_STRATEGY)
    if strategy.fetch("transport") == "header"
      checks["auth"] = actual.fetch("headers", {}).any? { |key, value| key.to_s.casecmp?(strategy.fetch("name")) && !value.to_s.empty? }
    end
    { "passed" => checks.values.all?, "checks" => checks, "actual" => actual, "expected" => expected }
  end

  def compare_result(actual, expected)
    checks = {
      "status" => actual["status"] == expected.fetch("status"),
      "provider_operation_id" => actual["provider_operation_id"] == expected.fetch("provider_operation_id")
    }
    checks["amount"] = actual["amount"] == expected["amount"] if expected.key?("amount")
    { "passed" => checks.values.all?, "checks" => checks, "actual" => actual, "expected" => expected }
  end

  def compare_callback(actual, expected)
    checks = {
      "status" => actual["status"] == expected.fetch("status"),
      "event" => actual["event"] == expected.fetch("event"),
      "action" => actual["action"] == expected.fetch("action")
    }
    { "passed" => checks.values.all?, "checks" => checks, "actual" => actual, "expected" => expected }
  end

  def load_service(path)
    before = Provider.constants
    load path
    candidates = Provider.constants.reject { |name| before.include?(name) }.filter_map do |name|
      value = Provider.const_get(name)
      value if value.is_a?(Class) && value < Provider::BaseService
    end
    candidates.fetch(0)
  end

  def aggregate(results)
    total = results.length
    {
      "providers_total" => total,
      "providers_passed" => results.count { |item| item["passed"] },
      "spec_only_accept_count" => results.count { |item| item["actual_decision"] == "ACCEPT" },
      "spec_only_accept_rate" => percentage(results.count { |item| item["actual_decision"] == "ACCEPT" }, total),
      "generation_pass_count" => results.count { |item| item.dig("generation", "passed") },
      "generation_pass_rate" => percentage(results.count { |item| item.dig("generation", "passed") }, total),
      "behavioral_vector_pass_count" => results.count { |item| item.fetch("behavioral_vectors", []).all? { |vector| vector["passed"] } && !item.fetch("behavioral_vectors", []).empty? },
      "behavioral_vector_pass_rate" => percentage(results.count { |item| item.fetch("behavioral_vectors", []).all? { |vector| vector["passed"] } && !item.fetch("behavioral_vectors", []).empty? }, total),
      "semantic_pass_count" => results.count { |item| item.dig("semantic", "passed") },
      "operation_semantic_accuracy" => area_percentage(results, "operations"),
      "money_semantic_accuracy" => area_percentage(results, "money"),
      "status_semantic_accuracy" => area_percentage(results, "statuses"),
      "auth_semantic_accuracy" => area_percentage(results, "auth"),
      "webhook_semantic_accuracy" => area_percentage(results, "webhook"),
      "idempotency_semantic_accuracy" => area_percentage(results, "idempotency"),
      "field_mapping_semantic_accuracy" => area_percentage(results, "fields"),
      "corpus_pass" => results.all? { |item| item["passed"] }
    }
  end

  def area_percentage(results, area)
    percentage(results.count { |item| item.dig("semantic", "areas", area) == true }, results.length)
  end

  def contains_value?(value, expected)
    case value
    when Hash
      value.any? { |key, item| (key.to_s == "provenance" && item.to_s == expected) || contains_value?(item, expected) }
    when Array
      value.any? { |item| contains_value?(item, expected) }
    else
      value.to_s == expected
    end
  end

  def percentage(numerator, denominator)
    return nil if denominator.zero?

    (100.0 * numerator / denominator).round(1)
  end

  class SemanticComparator
    def initialize(expected, actual)
      @expected = expected
      @actual = actual
      @failures = []
      @areas = {}
    end

    def compare
      compare_operations
      compare_money
      compare_auth
      compare_statuses
      compare_webhook
      compare_idempotency
      compare_fields
      { "passed" => @failures.empty?, "failures" => @failures, "areas" => @areas }
    end

    private

    def compare_operations
      @expected.fetch("operations").each do |role, expectation|
        actual = Array(@actual["endpoints"]).find { |item| item["canonical"] == role }
        check("operations", actual && actual["method"] == expectation["method"] && actual["path"] == expectation["path"] && actual["operation_id"] == expectation["operation_id"], "operation #{role} does not match ground truth")
      end
    end

    def compare_money
      expected = @expected.fetch("money")
      actual = @actual.fetch("money")
      check("money", actual.dig("host", "unit") == expected["host_unit"], "host money unit mismatch")
      check("money", actual.dig("provider", "unit") == expected["provider_unit"], "provider money unit mismatch")
      check("money", actual.dig("provider", "scale") == expected["scale"], "money scale mismatch")
      check("money", actual.dig("request_conversion", "factor") == expected["request_factor"], "request money factor mismatch")
      check("money", actual.dig("response_conversion", "factor_decimal") == expected["response_factor_decimal"], "response money factor mismatch")
    end

    def compare_auth
      expected = @expected.fetch("auth")
      actual = @actual.dig("auth", "strategy") || {}
      check("auth", actual["kind"] == expected["kind"], "auth kind mismatch")
      check("auth", actual["transport"] == expected["location"], "auth location mismatch")
      check("auth", actual["name"] == expected["name"], "auth name mismatch")
    end

    def compare_statuses
      expected = @expected.fetch("statuses")
      actual = Array(@actual["statuses"]).to_h { |item| [item["provider_value"], item["canonical_value"]] }
      expected.each { |provider, canonical| check("statuses", actual[provider] == canonical, "status #{provider} mapping mismatch") }
    end

    def compare_webhook
      expected = @expected.fetch("webhook")
      actual = @actual.fetch("webhook")
      if expected["mode"] == "polling_only"
        check("webhook", actual["mode"].to_s == "polling_only" || (actual["endpoint"].nil? && actual["decision"] == "ACCEPT"), "polling-only webhook mode mismatch")
        return
      end
      check("webhook", actual.dig("endpoint").to_s.end_with?(expected.fetch("endpoint")), "webhook endpoint mismatch")
      check("webhook", actual.dig("signature", "algorithm") == expected["algorithm"], "webhook algorithm mismatch")
      check("webhook", actual.dig("signature", "header") == expected["header"], "webhook header mismatch")
      check("webhook", actual.dig("signature", "input") == expected["input"], "webhook input mismatch")
      check("webhook", actual.dig("signature", "encoding") == expected["encoding"], "webhook encoding mismatch")
      expected.fetch("events").each { |event, canonical| check("webhook", actual.dig("events", event) == canonical, "webhook event #{event} mapping mismatch") }
    end

    def compare_idempotency
      expected = @expected.fetch("idempotency")
      actual = @actual.fetch("idempotency")
      check("idempotency", actual["header"] == expected["header"], "idempotency header mismatch")
      check("idempotency", actual["spec_required"] == expected["spec_required"], "idempotency requiredness mismatch")
    end

    def compare_fields
      Array(@expected["fields"]).each do |expectation|
        actual = Array(@actual["field_mappings"]).find do |item|
          item["canonical_path"] == expectation["canonical_path"] && item["provider_path"] == expectation["provider_path"] && item["direction"] == expectation["direction"]
        end
        check("fields", !actual.nil?, "field mapping missing: #{expectation.inspect}")
        next unless actual

        check("fields", actual["factor"] == expectation["factor"], "field factor mismatch: #{expectation.inspect}") if expectation.key?("factor")
        check("fields", actual["transform"] == expectation["transform"], "field transform mismatch: #{expectation.inspect}") if expectation.key?("transform")
      end
    end

    def check(area, condition, message)
      @areas[area] = false if !condition
      @areas[area] = true unless @areas.key?(area) && @areas[area] == false
      @failures << message unless condition
    end
  end
end

SpecOnlySuccessV1.run if $PROGRAM_NAME == __FILE__
