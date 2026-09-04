# frozen_string_literal: true

module ProviderCompiler

  class Evidence
    attr_reader :data

    def initialize(source:, locations:, excerpt: nil, note: nil)
      @data = Immutable.deep_freeze(
        "source" => source,
        "locations" => Array(locations),
        "excerpt" => excerpt,
        "note" => note
      )
      freeze
    end

    def to_h
      data
    end
  end

  class Decision
    OUTCOMES = %w[ACCEPT REVIEW_REQUIRED UNKNOWN].freeze
    SEVERITIES = %w[INFO WARNING BLOCKING].freeze
    attr_reader :data

    def initialize(id:, outcome:, severity:, candidate:, evidence:, rationale:, conflicts: [])
      raise ArgumentError, "invalid outcome" unless OUTCOMES.include?(outcome)
      raise ArgumentError, "invalid severity" unless SEVERITIES.include?(severity)

      @data = Immutable.deep_freeze(
        "decision_id" => id,
        "outcome" => outcome,
        "severity" => severity,
        "candidate" => candidate,
        "evidence" => Array(evidence).map(&:to_h),
        "conflicts" => conflicts,
        "rationale" => rationale
      )
      freeze
    end

    def to_h
      data
    end

    def blocking?
      data["severity"] == "BLOCKING"
    end

    def review?
      data["outcome"] == "REVIEW_REQUIRED"
    end
  end

  class AnalysisResult
    attr_reader :section, :decisions

    def initialize(section:, decisions:)
      @section = section
      @decisions = decisions.freeze
      freeze
    end
  end

end
