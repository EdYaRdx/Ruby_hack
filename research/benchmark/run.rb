# frozen_string_literal: true

# Real mutation benchmark harness.
#
# The mutation descriptions/labels remain hand-authored in mutations.json. This
# file only materializes those descriptions into OpenAPI documents and invokes
# the production ProviderCompiler pipeline. It must not contain analyzer policy
# shortcuts or expected-outcome branches.

require "fileutils"
require "json"
require "tmpdir"
require "yaml"

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "provider_compiler"
require_relative "semantic_comparator"

module RealMutationBenchmark
  ROOT = File.expand_path("../..", __dir__)
  MUTATION_PATH = File.join(__dir__, "mutations.json")
  ADJUDICATION_PATH = File.join(__dir__, "adjudications.yml")
  SEMANTIC_GROUND_TRUTH_PATH = File.join(__dir__, "semantic_ground_truth.yml")
  SOURCE_PATH = File.join(ROOT, "fixtures", "novapay_provider_api.yaml")
  PROFILE_PATH = File.join(ROOT, "profiles", "space_payments_v1.yml")
  DEFAULTS_PATH = File.join(ROOT, "fixtures", "novapay_case_defaults.yml")
  OUTPUT_PATH = ENV.fetch("BENCHMARK_OUTPUT", File.join(ROOT, "tmp", "benchmark", "results.json"))

  module_function

  def run
    mutations = JSON.parse(File.read(MUTATION_PATH, encoding: "UTF-8"))
    adjudications = YAML.safe_load(File.read(ADJUDICATION_PATH, encoding: "UTF-8"), aliases: true).fetch("cases", {})
    semantic_ground_truth = YAML.safe_load(File.read(SEMANTIC_GROUND_TRUTH_PATH, encoding: "UTF-8"), aliases: true).fetch("cases", {})
    source = YAML.safe_load(File.read(SOURCE_PATH, encoding: "UTF-8"), aliases: true)
    examples = ProviderCompiler::CaseDefaults.load(DEFAULTS_PATH).examples
    run_id = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
    work_dir = File.join(ROOT, "tmp", "benchmark", "runs", run_id)
    FileUtils.mkdir_p(work_dir)

    results = mutations.map do |mutation|
      execute_case(mutation, source, work_dir, examples, adjudications, semantic_ground_truth.fetch(mutation.fetch("id"), {}))
    end
    report = {
      "schema_version" => 1,
      "benchmark" => "real_mutation_benchmark",
      "methodology" => "hand-authored mutation -> OpenAPI loader/refs/facts -> real analyzers -> Review Manifest -> Blueprint -> conditional deterministic generation",
      "source" => File.basename(SOURCE_PATH),
      "mutations_file" => File.basename(MUTATION_PATH),
      "adjudications_file" => File.basename(ADJUDICATION_PATH),
      "semantic_ground_truth_file" => File.basename(SEMANTIC_GROUND_TRUTH_PATH),
      "cases" => results,
      "aggregate" => aggregate(results)
    }
    FileUtils.mkdir_p(File.dirname(OUTPUT_PATH))
    File.write(OUTPUT_PATH, JSON.pretty_generate(report) + "\n", encoding: "UTF-8")
    puts JSON.pretty_generate(report.fetch("aggregate"))
    puts "Wrote #{OUTPUT_PATH}"
    report
  end

  def execute_case(mutation, source, work_dir, examples, adjudications, semantic_case)
    id = mutation.fetch("id")
    adjudication = adjudications[id]
    effective_expected = adjudication ? adjudication.fetch("adjudicated_decision") : mutation.fetch("expected_decision")
    document, extra_files = Mutator.new(source).apply(id)
    case_dir = File.join(work_dir, id)
    FileUtils.mkdir_p(case_dir)
    spec_path = File.join(case_dir, "provider_api.yaml")
    File.write(spec_path, YAML.dump(document), encoding: "UTF-8")
    extra_files.each do |name, content|
      File.write(File.join(case_dir, name), YAML.dump(content), encoding: "UTF-8")
    end

    pipeline = ProviderCompiler::Pipeline.new(
      spec_path: spec_path,
      profile_path: PROFILE_PATH,
      defaults_path: DEFAULTS_PATH
    )
    blueprint = pipeline.blueprint
    manifest = pipeline.manifest.to_h
    actual_decision = blueprint.fetch("decision")
    generation = generate_if_accepted(blueprint, manifest, case_dir, examples)
    semantic_validation = SemanticBenchmark::Comparator.new.compare(
      expected_decision: effective_expected,
      expected_case: semantic_case,
      actual_decision: actual_decision,
      blueprint: blueprint,
      generation: generation
    )
    actual = {
      "decision" => actual_decision,
      "source" => source_summary(blueprint),
      "operation_mapping" => operation_mapping(blueprint),
      "money" => money_summary(blueprint),
      "auth" => auth_summary(blueprint),
      "status" => status_summary(blueprint),
      "webhook" => webhook_summary(blueprint),
      "idempotency" => idempotency_summary(blueprint),
      "manifest" => manifest.fetch("summary"),
      "generation" => generation,
      "semantic_validation" => semantic_validation
    }
    expected = mutation.slice("expected_decision", "expected_operation", "critical", "area", "expected").merge("effective_decision" => effective_expected, "semantic" => semantic_case.fetch("semantics", {}), "safety" => semantic_case.fetch("safety", {}))
    {
      "case_id" => id,
      "expected" => expected,
      "adjudication" => adjudication,
      "actual" => actual,
      "passed" => semantic_validation.fetch("passed"),
      "failure_class" => semantic_validation.fetch("passed") ? nil : classify_failure(effective_expected, actual, semantic_validation)
    }
  rescue ProviderCompiler::Error, ProviderCompiler::ValidationError, Psych::Exception, Errno::ENOENT => e
    error = { "class" => e.class.name, "message" => e.message }
    semantic_validation = SemanticBenchmark::Comparator.new.compare(
      expected_decision: effective_expected,
      expected_case: semantic_case,
      actual_decision: "UNKNOWN",
      blueprint: nil,
      generation: nil,
      error: error
    )
    {
      "case_id" => mutation.fetch("id"),
      "expected" => mutation.slice("expected_decision", "expected_operation", "critical", "area", "expected").merge("effective_decision" => effective_expected, "semantic" => semantic_case.fetch("semantics", {}), "safety" => semantic_case.fetch("safety", {})),
      "adjudication" => adjudication,
      "actual" => { "decision" => "UNKNOWN", "error" => error, "semantic_validation" => semantic_validation },
      "passed" => semantic_validation.fetch("passed"),
      "failure_class" => semantic_validation.fetch("passed") ? nil : classify_failure(effective_expected, { "decision" => "UNKNOWN" }, semantic_validation)
    }
  end

  def generate_if_accepted(blueprint, manifest, case_dir, examples)
    return { "status" => "not_attempted", "reason" => blueprint.fetch("decision") } unless blueprint.fetch("decision") == "ACCEPT"

    begin
      ProviderCompiler::BlueprintValidator.new.validate!(blueprint, ProviderCompiler::BaseServiceProfile.load(PROFILE_PATH))
      output_dir = File.join(case_dir, "generated")
      ProviderCompiler::DeterministicGenerator.new.generate(blueprint, manifest, output_dir, examples: examples)
      verification = ProviderCompiler::Verification.new.verify(output_dir)
      { "status" => verification.fetch("passed") ? "passed" : "failed", "verification" => verification }
    rescue ProviderCompiler::Error, ProviderCompiler::ValidationError, Errno::ENOENT => e
      { "status" => "failed", "error" => { "class" => e.class.name, "message" => e.message } }
    end
  end

  def operation_mapping(blueprint)
    blueprint.fetch("operations").map { |item| item.slice("operation_id", "canonical", "method", "path") } +
      blueprint.fetch("extra_operations").map { |item| item.slice("operation_id", "kind", "method", "path") }
  end

  def source_summary(blueprint)
    source = blueprint.fetch("source")
    inputs = source.fetch("fingerprint_inputs")
    {
      "spec_fingerprint" => source.fetch("spec_fingerprint"),
      "root_document_sha256" => source.fetch("root_document_sha256"),
      "resolved_local_ref_count" => Array(inputs.fetch("resolved_local_ref_closure")).length,
      "resolved_files" => inputs.fetch("resolved_files").keys
    }
  end

  def money_summary(blueprint)
    money = blueprint.fetch("money")
    {
      "decision" => money["decision"],
      "host_unit" => money.dig("host", "unit"),
      "provider_unit" => money.dig("provider", "unit"),
      "scale" => money.dig("provider", "scale"),
      "request_conversion" => money["request_conversion"],
      "response_conversion" => money["response_conversion"]
    }
  end

  def auth_summary(blueprint)
    auth = blueprint.fetch("auth")
    { "selected" => auth["selected"], "strategy" => auth["strategy"], "decision" => auth.dig("schemes", 0, "decision") }
  end

  def status_summary(blueprint)
    statuses = blueprint.fetch("statuses")
    { "count" => statuses.length, "unknown" => statuses.select { |item| item["canonical_value"] == "UNKNOWN" }.map { |item| item["provider_value"] }, "mapping" => statuses.to_h { |item| [item["provider_value"], item["canonical_value"]] } }
  end

  def webhook_summary(blueprint)
    webhook = blueprint.fetch("webhook")
    { "decision" => webhook["decision"], "endpoint" => webhook["endpoint"], "signature" => webhook["signature"] }
  end

  def idempotency_summary(blueprint)
    blueprint.fetch("idempotency").slice("header", "spec_required", "spec_evidence_source", "adapter_policy", "retry_policy")
  end

  def classify_failure(expected, actual, semantic_validation)
    actual_decision = actual.fetch("decision")
    return "false_accept" if actual_decision == "ACCEPT" && expected != "ACCEPT"
    return "over_abstention" if actual_decision != "ACCEPT" && expected == "ACCEPT"
    return "semantic_mismatch" unless semantic_validation.fetch("semantic_pass")
    return "safety_mismatch" unless semantic_validation.fetch("safety_pass")
    return "generation_runtime_failure" unless semantic_validation.fetch("generation_runtime_pass")
    return "decision_mismatch" if actual_decision != expected

    "unknown"
  end

  def aggregate(results)
    total = results.length
    passed = results.count { |item| item["passed"] }
    decision_passed = results.count { |item| item.dig("actual", "semantic_validation", "decision_pass") }
    accepts = results.select { |item| item.dig("actual", "decision") == "ACCEPT" }
    expected_accepts = results.count { |item| item.dig("expected", "effective_decision") == "ACCEPT" }
    correct_accepts = accepts.count { |item| item.dig("expected", "effective_decision") == "ACCEPT" }
    critical_false_accepts = results.select do |item|
      next false unless item.dig("expected", "critical")

      decision_false_accept = item.dig("actual", "decision") == "ACCEPT" && item.dig("expected", "effective_decision") != "ACCEPT"
      unsafe_accept = item.dig("actual", "decision") == "ACCEPT" && item.dig("expected", "effective_decision") == "ACCEPT" && (
        !item.dig("actual", "semantic_validation", "semantic_pass") ||
        !item.dig("actual", "semantic_validation", "safety_pass") ||
        !item.dig("actual", "semantic_validation", "generation_runtime_pass")
      )
      decision_false_accept || unsafe_accept
    end
    generation_attempts = results.select { |item| item.dig("actual", "generation", "status") && item.dig("actual", "generation", "status") != "not_attempted" }
    syntax_entries = generation_attempts.flat_map { |item| Array(item.dig("actual", "generation", "verification", "syntax")) }
    area_accuracy = results.group_by { |item| item.dig("expected", "area") }.transform_values do |items|
      percentage(items.count { |item| item.dig("actual", "semantic_validation", "passed") }, items.length)
    end
    semantic_accept_cases = results.select { |item| item.dig("expected", "effective_decision") == "ACCEPT" }
    semantic_area_accuracy = %w[operations money statuses auth webhook idempotency field_mappings].to_h do |area|
      relevant = results.select { |item| item.dig("actual", "semantic_validation", "semantic_areas", area) != nil }
      [area, percentage(relevant.count { |item| item.dig("actual", "semantic_validation", "semantic_areas", area) }, relevant.length)]
    end
    {
      "cases_total" => total,
      "cases_passed" => passed,
      "cases_failed" => total - passed,
      "decision_accuracy" => percentage(decision_passed, total),
      "safe_decision_coverage" => percentage(passed, total),
      "original_label_accuracy" => percentage(results.count { |item| item.dig("actual", "decision") == item.dig("expected", "expected_decision") }, total),
      "automatic_accept_rate" => percentage(accepts.length, total),
      "accept_count" => accepts.length,
      "accept_precision" => percentage(correct_accepts, accepts.length),
      "expected_accept_count" => expected_accepts,
      "review_required_count" => results.count { |item| item.dig("actual", "decision") == "REVIEW_REQUIRED" },
      "unknown_count" => results.count { |item| item.dig("actual", "decision") == "UNKNOWN" },
      "review_required_rate" => percentage(results.count { |item| item.dig("actual", "decision") == "REVIEW_REQUIRED" }, total),
      "unknown_rate" => percentage(results.count { |item| item.dig("actual", "decision") == "UNKNOWN" }, total),
      "legacy_decision_only_automatic_coverage" => percentage(results.select { |item| item.dig("expected", "effective_decision") != "UNKNOWN" }.count { |item| item.dig("actual", "semantic_validation", "decision_pass") }, results.count { |item| item.dig("expected", "effective_decision") != "UNKNOWN" }),
      "semantic_accept_accuracy" => percentage(semantic_accept_cases.count { |item| item.dig("actual", "decision") == "ACCEPT" && item.dig("actual", "semantic_validation", "semantic_pass") }, semantic_accept_cases.length),
      "operation_semantic_accuracy" => semantic_area_accuracy["operations"],
      "money_semantic_accuracy" => semantic_area_accuracy["money"],
      "status_semantic_accuracy" => semantic_area_accuracy["statuses"],
      "auth_semantic_accuracy" => semantic_area_accuracy["auth"],
      "webhook_semantic_accuracy" => semantic_area_accuracy["webhook"],
      "idempotency_semantic_accuracy" => semantic_area_accuracy["idempotency"],
      "field_mapping_semantic_accuracy" => semantic_area_accuracy["field_mappings"],
      "critical_false_accept_count" => critical_false_accepts.length,
      "critical_false_accept_cases" => critical_false_accepts.map { |item| item.fetch("case_id") },
      "critical_false_accept_rate" => percentage(critical_false_accepts.length, results.count { |item| item.dig("expected", "critical") }),
      "generation_pass_count" => generation_attempts.count { |item| item.dig("actual", "generation", "status") == "passed" },
      "generation_attempt_count" => generation_attempts.length,
      "generation_success_rate" => percentage(generation_attempts.count { |item| item.dig("actual", "generation", "status") == "passed" }, generation_attempts.length),
      "generated_syntax_pass_rate" => percentage(syntax_entries.count { |item| item["passed"] }, syntax_entries.length),
      "disputed_case_count" => results.count { |item| item["adjudication"] },
      "disputed_cases" => results.select { |item| item["adjudication"] }.map { |item| item.fetch("case_id") },
      "area_decision_accuracy" => area_accuracy,
      "area_semantic_accuracy" => semantic_area_accuracy,
      "operation_mapping_accuracy" => area_accuracy["operation"],
      "money_mapping_accuracy" => area_accuracy["field_money"],
      "status_mapping_accuracy" => area_accuracy["status"],
      "auth_mapping_accuracy" => area_accuracy["auth"],
      "webhook_detection_security_accuracy" => area_accuracy["webhook"],
      "field_mapping_accuracy" => area_accuracy["field_money"],
      "failure_classes" => results.reject { |item| item["passed"] }.group_by { |item| item["failure_class"] }.transform_values(&:length)
    }
  end

  def percentage(numerator, denominator)
    return nil if denominator.zero?

    (100.0 * numerator / denominator).round(1)
  end

  class Mutator
    def initialize(source)
      @source = Marshal.load(Marshal.dump(source))
    end

    def apply(id)
      document = Marshal.load(Marshal.dump(@source))
      extra_files = {}
      case id
      when "M01" then rename_path(document, "/payouts", "/transfers")
      when "M02" then rename_path(document, "/payouts", "/withdrawals")
      when "M03" then create_operation(document)["operationId"] = "initiateTransfer"
      when "M04" then create_operation(document)["operationId"] = "makeWithdrawal"
      when "M05" then create_operation(document).delete("operationId")
      when "M06" then create_operation(document)["tags"] = ["Transfers"]
      when "M07" then create_operation(document)["summary"] = "Submit transaction"
      when "M08" then rename_request_property(document, "amount", "sum")
      when "M09" then rename_request_property(document, "amount", "total")
      when "M10" then nest_money_value(document)
      when "M11" then request_amount(document)["description"] = "Integer amount in minor units (kopecks)"
      when "M12" then request_amount(document)["description"] = "Amount in major RUB units"
      when "M13" then remove_amount_descriptions(document)
      when "M14" then replace_everywhere(document, "completed", "settled")
      when "M15" then replace_everywhere(document, "completed", "success")
      when "M16" then replace_everywhere(document, "failed", "declined")
      when "M17" then replace_everywhere(document, "cancelled", "voided")
      when "M18" then add_unknown_terminal_status(document, "chargeback")
      when "M19" then bearer_auth(document)
      when "M20" then api_key_query(document)
      when "M21" then rename_auth_header(document, "X-Client-Token")
      when "M22" then rename_idempotency_header(document, "X-Request-Token")
      when "M23" then create_operation(document).fetch("parameters").clear
      when "M24" then rename_path(document, "/webhooks/payout", "/callbacks/payment")
      when "M25" then rename_path(document, "/webhooks/payout", "/notifications/payout")
      when "M26" then convert_to_callback(document)
      when "M27" then convert_to_top_level_webhook(document)
      when "M28" then document.fetch("paths").delete("/webhooks/payout")
      when "M29" then remove_hmac_description(document)
      when "M30" then add_extra_operation(document, "/limits", "getLimits", "Limits")
      when "M31" then duplicate_balance_as_invalid_operation(document)
      when "M32" then rename_cancel_to_void(document)
      when "M33"
        recipient = document.dig("components", "schemas", "Recipient")
        extra_files["components.yml"] = { "components" => { "schemas" => { "Recipient" => recipient } } }
        document.dig("components", "schemas", "CreatePayoutRequest", "properties", "recipient")["$ref"] = "components.yml#/components/schemas/Recipient"
      when "M34"
        document.dig("components", "schemas", "CreatePayoutRequest", "properties", "recipient")["$ref"] = "missing.yml#/components/schemas/Recipient"
      when "M35"
        create_operation(document)["operationId"] = "createTransaction"
        rename_path(document, "/payouts", "/transactions")
      when "M36" then delete_keys(document, "description")
      when "M37" then delete_keys(document, "example", "examples")
      else raise ArgumentError, "unknown mutation #{id}"
      end
      [document, extra_files]
    end

    private

    def create_operation(document)
      document.fetch("paths").fetch("/payouts").fetch("post")
    end

    def request_schema(document)
      document.dig("components", "schemas", "CreatePayoutRequest")
    end

    def request_amount(document)
      request_schema(document).dig("properties", "amount")
    end

    def rename_path(document, old_path, new_path)
      document.fetch("paths")[new_path] = document.fetch("paths").delete(old_path)
    end

    def rename_request_property(document, old_name, new_name)
      schema = request_schema(document)
      schema["properties"][new_name] = schema["properties"].delete(old_name)
      schema["required"] = schema.fetch("required").map { |field| field == old_name ? new_name : field }
    end

    def nest_money_value(document)
      schema = request_schema(document)
      amount = schema["properties"].delete("amount")
      schema["properties"]["money"] = { "type" => "object", "required" => ["value", "currency"], "properties" => { "value" => amount, "currency" => schema["properties"].fetch("currency") } }
      schema["required"] = schema.fetch("required").reject { |field| %w[amount currency].include?(field) } + ["money"]
    end

    def remove_amount_descriptions(document)
      request_amount(document).delete("description")
      create_operation(document)["description"] = "Creates a payout to a recipient."
    end

    def replace_everywhere(node, old_value, new_value)
      case node
      when Hash
        node.each { |key, value| node[key] = value == old_value ? new_value : replace_everywhere(value, old_value, new_value) }
      when Array
        node.map! { |value| value == old_value ? new_value : replace_everywhere(value, old_value, new_value) }
      else
        node
      end
    end

    def add_unknown_terminal_status(document, status)
      %w[PayoutResponse WebhookPayload].each { |name| document.dig("components", "schemas", name, "properties", "status", "enum") << status }
    end

    def bearer_auth(document)
      document["components"]["securitySchemes"] = { "BearerAuth" => { "type" => "http", "scheme" => "bearer" } }
      document["paths"].each_value do |item|
        item.each_value { |operation| operation["security"] = [{ "BearerAuth" => [] }] if operation.is_a?(Hash) && operation.key?("security") }
      end
    end

    def api_key_query(document)
      scheme = document.dig("components", "securitySchemes", "ApiKeyAuth")
      scheme["in"] = "query"
    end

    def rename_auth_header(document, new_name)
      document.dig("components", "securitySchemes", "ApiKeyAuth")["name"] = new_name
    end

    def rename_idempotency_header(document, new_name)
      document.dig("components", "parameters", "IdempotencyKey")["name"] = new_name
    end

    def convert_to_callback(document)
      webhook = document.fetch("paths").delete("/webhooks/payout").fetch("post")
      create_operation(document)["callbacks"] = { "payoutStatus" => { "{$request.body#/callback_url}" => { "post" => webhook } } }
    end

    def convert_to_top_level_webhook(document)
      webhook = document.fetch("paths").delete("/webhooks/payout").fetch("post")
      document["openapi"] = "3.1.0"
      document["webhooks"] = { "payoutNotifications" => { "post" => webhook } }
    end

    def remove_hmac_description(document)
      operation = document.fetch("paths").fetch("/webhooks/payout").fetch("post")
      operation["description"] = "Provider sends a signed notification."
      operation.fetch("parameters").first["description"] = "Signature of the request body"
    end

    def add_extra_operation(document, path, operation_id, summary)
      document.fetch("paths")[path] = { "get" => { "operationId" => operation_id, "summary" => summary, "responses" => { "200" => { "description" => "ok" } } } }
    end

    def duplicate_balance_as_invalid_operation(document)
      document.fetch("paths").fetch("/balance")["get"] = [document.fetch("paths").fetch("/balance").fetch("get"), document.fetch("paths").fetch("/balance").fetch("get")]
    end

    def rename_cancel_to_void(document)
      rename_path(document, "/payouts/{payout_id}/cancel", "/payouts/{payout_id}/void")
      operation = document.fetch("paths").fetch("/payouts/{payout_id}/void").fetch("post")
      operation["operationId"] = "voidPayout"
      operation["summary"] = "Void payout"
    end

    def delete_keys(node, *keys)
      case node
      when Hash
        keys.each { |key| node.delete(key) }
        node.each_value { |value| delete_keys(value, *keys) }
      when Array
        node.each { |value| delete_keys(value, *keys) }
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  report = RealMutationBenchmark.run
  exit 1 if report.dig("aggregate", "critical_false_accept_count").to_i.positive?
end
