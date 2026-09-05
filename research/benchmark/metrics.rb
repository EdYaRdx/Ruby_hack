# frozen_string_literal: true

# Reporting-only metric helpers. These values describe benchmark evidence and
# do not participate in compiler decisions or semantic inference.
module BenchmarkMetrics
  module_function

  def from_manifest_summary(summary, total_specs: 1, fully_auto_ready_specs: nil, critical_false_accepts: 0, unsafe_generation_attempts: 0)
    summary = summary || {}
    total_decisions = summary.fetch("decisions", 0).to_i
    accepted_decisions = summary.fetch("accepted", 0).to_i
    review_required_decisions = summary.fetch("review_required", 0).to_i
    unknown_decisions = summary.fetch("unknown", 0).to_i
    blocking_entries = summary.fetch("blocking", 0).to_i
    fully_auto_ready_specs = if fully_auto_ready_specs.nil?
                               total_specs.to_i == 1 && review_required_decisions.zero? && blocking_entries.zero? ? 1 : 0
                             else
                               fully_auto_ready_specs.to_i
                             end

    {
      "decision_level" => {
        "total_decisions" => total_decisions,
        "accepted_decisions" => accepted_decisions,
        "review_required_decisions" => review_required_decisions,
        "unknown_decisions" => unknown_decisions,
        "blocking_entries" => blocking_entries,
        "decision_automation_rate" => percentage(accepted_decisions, total_decisions),
        "review_rate" => percentage(review_required_decisions, total_decisions)
      },
      "spec_level" => {
        "total_specs" => total_specs.to_i,
        "fully_auto_ready_specs" => fully_auto_ready_specs,
        "fully_auto_ready_rate" => percentage(fully_auto_ready_specs, total_specs)
      },
      "safety" => {
        "critical_false_accepts" => critical_false_accepts.to_i,
        "unsafe_generation_attempts" => unsafe_generation_attempts.to_i
      },
      "formulas" => {
        "decision_automation_rate" => "accepted_decisions / total_decisions",
        "review_rate" => "review_required_decisions / total_decisions",
        "fully_auto_ready_rate" => "specs_with_zero_review_and_zero_blocking / total_specs",
        "critical_false_accepts" => "unsafe ACCEPTs for hand-authored critical cases",
        "unsafe_generation_attempts" => "generation attempts while a critical decision is unresolved"
      }
    }
  end

  def percentage(numerator, denominator)
    return nil if denominator.to_i.zero?

    (100.0 * numerator.to_f / denominator.to_f).round(1)
  end
end
