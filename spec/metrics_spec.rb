# frozen_string_literal: true

require_relative "../research/benchmark/metrics"

RSpec.describe BenchmarkMetrics do
  def summary(decisions:, accepted:, review_required:, blocking:)
    {
      "decisions" => decisions,
      "accepted" => accepted,
      "review_required" => review_required,
      "unknown" => 0,
      "blocking" => blocking
    }
  end

  it "keeps decision automation distinct from full-spec readiness" do
    metrics = described_class.from_manifest_summary(
      summary(decisions: 14, accepted: 10, review_required: 4, blocking: 3),
      total_specs: 1,
      fully_auto_ready_specs: 0
    )

    expect(metrics.dig("decision_level", "decision_automation_rate")).to eq(71.4)
    expect(metrics.dig("decision_level", "review_rate")).to eq(28.6)
    expect(metrics.dig("spec_level", "fully_auto_ready_rate")).to eq(0.0)
    expect(metrics.dig("decision_level", "blocking_entries")).to eq(3)
  end

  it "calculates an aggregate mutation lane with its own spec denominator" do
    metrics = described_class.from_manifest_summary(
      summary(decisions: 98, accepted: 74, review_required: 24, blocking: 17),
      total_specs: 7,
      fully_auto_ready_specs: 0
    )

    expect(metrics.dig("decision_level", "decision_automation_rate")).to eq(75.5)
    expect(metrics.dig("decision_level", "review_rate")).to eq(24.5)
    expect(metrics.dig("spec_level", "fully_auto_ready_rate")).to eq(0.0)
  end

  it "returns nil for rates with a zero denominator" do
    metrics = described_class.from_manifest_summary(
      summary(decisions: 0, accepted: 0, review_required: 0, blocking: 0),
      total_specs: 0,
      fully_auto_ready_specs: 0
    )

    expect(metrics.dig("decision_level", "decision_automation_rate")).to be_nil
    expect(metrics.dig("decision_level", "review_rate")).to be_nil
    expect(metrics.dig("spec_level", "fully_auto_ready_rate")).to be_nil
  end

  it "keeps safety metrics explicit and independent of decision rates" do
    metrics = described_class.from_manifest_summary(
      summary(decisions: 1, accepted: 1, review_required: 0, blocking: 0),
      critical_false_accepts: 0,
      unsafe_generation_attempts: 0
    )

    expect(metrics.fetch("safety")).to eq(
      "critical_false_accepts" => 0,
      "unsafe_generation_attempts" => 0
    )
  end
end
