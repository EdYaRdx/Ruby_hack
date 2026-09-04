# frozen_string_literal: true

require_relative "../research/benchmark/semantic_comparator"

RSpec.describe SemanticBenchmark::Comparator do
  subject(:comparator) { described_class.new }

  let(:accept_expected) do
    {
      "semantics" => {
        "operations" => {
          "create_request" => { "method" => "POST", "path" => "/payouts" }
        },
        "money" => {
          "request_conversion" => { "operation" => "multiply", "factor_decimal" => "100" }
        }
      }
    }
  end

  let(:accept_blueprint) do
    {
      "operations" => [{ "canonical" => "create_request", "method" => "POST", "path" => "/payouts" }],
      "money" => {
        "request_conversion" => { "status" => "resolved", "operation" => "multiply", "factor_decimal" => "100" }
      },
      "decisions" => [],
      "unknowns" => []
    }
  end

  let(:runtime_pass) { { "status" => "passed", "verification" => { "passed" => true } } }

  it "fails a correct ACCEPT when operation semantics are wrong" do
    blueprint = Marshal.load(Marshal.dump(accept_blueprint))
    blueprint["operations"][0]["path"] = "/transfers"

    result = comparator.compare(expected_decision: "ACCEPT", expected_case: accept_expected, actual_decision: "ACCEPT", blueprint: blueprint, generation: runtime_pass)

    expect(result.fetch("passed")).to be(false)
    expect(result.fetch("failed_checks")).to include("semantic.operations.create_request.path")
  end

  it "fails a correct ACCEPT when the money factor is wrong" do
    blueprint = Marshal.load(Marshal.dump(accept_blueprint))
    blueprint["money"]["request_conversion"]["factor_decimal"] = "1"

    result = comparator.compare(expected_decision: "ACCEPT", expected_case: accept_expected, actual_decision: "ACCEPT", blueprint: blueprint, generation: runtime_pass)

    expect(result.fetch("passed")).to be(false)
    expect(result.fetch("failed_checks")).to include("semantic.money.request_conversion.factor_decimal")
  end

  it "fails REVIEW_REQUIRED when a critical money conversion remains resolved" do
    expected = {
      "safety" => {
        "required_decisions" => [{ "id" => "money:amount-units", "outcome" => "REVIEW_REQUIRED", "severity" => "BLOCKING" }],
        "forbid_resolved" => ["money.request_conversion"]
      }
    }
    blueprint = {
      "money" => { "request_conversion" => { "status" => "resolved", "factor_decimal" => "100" } },
      "decisions" => [{ "decision_id" => "money:amount-units", "outcome" => "REVIEW_REQUIRED", "severity" => "BLOCKING" }],
      "unknowns" => []
    }

    result = comparator.compare(expected_decision: "REVIEW_REQUIRED", expected_case: expected, actual_decision: "REVIEW_REQUIRED", blueprint: blueprint, generation: { "status" => "not_attempted" })

    expect(result.fetch("passed")).to be(false)
    expect(result.fetch("failed_checks")).to include("safety.forbid_resolved.money.request_conversion")
  end

  it "fails UNKNOWN when the unsupported item is silently dropped" do
    blueprint = { "decisions" => [], "unknowns" => [] }

    result = comparator.compare(expected_decision: "UNKNOWN", expected_case: {}, actual_decision: "UNKNOWN", blueprint: blueprint, generation: nil)

    expect(result.fetch("passed")).to be(false)
    expect(result.fetch("failed_checks")).to include("safety.unknown_preserved")
  end

  it "passes when decision, semantic subset and runtime result all agree" do
    result = comparator.compare(expected_decision: "ACCEPT", expected_case: accept_expected, actual_decision: "ACCEPT", blueprint: accept_blueprint, generation: runtime_pass)

    expect(result.fetch("passed")).to be(true)
    expect(result.fetch("decision_pass")).to be(true)
    expect(result.fetch("semantic_pass")).to be(true)
    expect(result.fetch("generation_runtime_pass")).to be(true)
  end
end
