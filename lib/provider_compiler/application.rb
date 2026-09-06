# frozen_string_literal: true

module ProviderCompiler

  class AnalysisArtifactWriter
    RUNTIME_ARTIFACTS = %w[service.rb fixtures.json INTEGRATION.md contract_smoke.rb integration_readiness.json INTEGRATION_READINESS.md].freeze

    def self.write(output_dir, blueprint, manifest)
      FileUtils.mkdir_p(output_dir)
      RUNTIME_ARTIFACTS.each do |name|
        path = File.join(output_dir, name)
        File.delete(path) if File.file?(path)
      end
      Util.write_text(File.join(output_dir, "provider_blueprint.json"), Util.pretty_json(blueprint) + "\n")
      Util.write_text(File.join(output_dir, "review_manifest.json"), Util.pretty_json(manifest.to_h) + "\n")
      ["provider_blueprint.json", "review_manifest.json"].map { |name| File.join(output_dir, name) }
    end
  end

  class Pipeline
    attr_reader :source_document, :facts, :bundle, :blueprint, :manifest, :defaults

    attr_reader :review_override

    def initialize(spec_path:, profile_path:, defaults_path:, adapter_policy: "if_available", defaults_data: nil, overrides_path: nil, overrides_data: nil)
      @source_document = OpenAPILoader.new(spec_path).load
      OpenAPIValidator.new.validate!(@source_document)
      @facts = FactsBuilder.new.build(@source_document)
      @profile = BaseServiceProfile.load(profile_path)
      @review_override = overrides_data ? ReviewOverride.new(overrides_data, path: overrides_path) : (overrides_path ? ReviewOverride.load(overrides_path) : nil)
      base_defaults = defaults_data ? defaults_data : CaseDefaults.load(defaults_path).data
      if @review_override
        @review_override.validate_against!(@source_document, @profile)
        base_defaults = ReviewDefaults.merge(base_defaults, @review_override.defaults_overrides)
      end
      @defaults = CaseDefaults.new(base_defaults)
      @bundle = AnalyzerEngine.new(profile: @profile, defaults: @defaults, adapter_policy: adapter_policy).analyze(@facts)
      @review_override&.validate_against!(@source_document, @profile, known_decision_ids: @bundle.decisions.map { |decision| decision.to_h.fetch("decision_id") })
      @blueprint = BlueprintBuilder.new.build(@facts, @profile, @bundle)
      @manifest = ReviewManifest.new(source: @source_document.to_h, decisions: @bundle.decisions, blueprint_status: @blueprint["decision"], override: @review_override)
    end

    def validate_blueprint!
      BlueprintValidator.new.validate!(@blueprint, @profile)
    end
  end

  class CLI
    def self.run(argv)
      command = argv.shift || "help"
      options = default_options
      parser = option_parser(options)
      parser.parse!(argv)
      if options[:spec_explicit] && !options[:defaults_explicit]
        options[:defaults] = options.fetch(:empty_defaults)
        options[:defaults_origin] = "none"
      end
      case command
      when "analyze", "inspect", "generate", "verify"
        if command == "verify"
          result = Verification.new.verify(options.fetch(:out))
          puts JSON.pretty_generate(result)
          return result["passed"] ? 0 : 1
        end
        pipeline = Pipeline.new(spec_path: options.fetch(:spec), profile_path: options.fetch(:profile), defaults_path: options.fetch(:defaults), adapter_policy: options.fetch(:idempotency_policy), overrides_path: options[:overrides])
        if command == "inspect"
          puts JSON.pretty_generate(
            "summary" => pipeline.manifest.to_h.fetch("summary"),
            "inputs" => {
              "spec" => options.fetch(:spec),
              "profile" => options.fetch(:profile),
              "provider_defaults" => options[:defaults_origin] == "none" ? "none" : options.fetch(:defaults)
            }
          )
          return 0
        end
        if command == "analyze"
          AnalysisArtifactWriter.write(options.fetch(:out), pipeline.blueprint, pipeline.manifest)
          summary = pipeline.manifest.to_h.fetch("summary").merge(
            "decision" => pipeline.blueprint.fetch("decision"),
            "generation_ready" => pipeline.blueprint.fetch("decision") == "ACCEPT"
          )
          puts Util.pretty_json(summary)
          return 0
        end
        output = options.fetch(:out)
        generation_blocked = pipeline.blueprint.fetch("decision") != "ACCEPT" || Array(pipeline.blueprint["decisions"]).any? { |item| item["severity"] == "BLOCKING" }
        if generation_blocked
          DeterministicGenerator.new.generate(pipeline.blueprint, pipeline.manifest, output, examples: pipeline.defaults.examples, spec_document: pipeline.source_document.resolved)
          warn "Generation blocked; review artifacts written to #{output}"
          return 2
        end
        pipeline.validate_blueprint!
        DeterministicGenerator.new.generate(pipeline.blueprint, pipeline.manifest, output, examples: pipeline.defaults.examples, spec_document: pipeline.source_document.resolved)
        verification = Verification.new.verify(output)
        IntegrationReadiness.write(output, IntegrationReadiness.build(pipeline, generated: true, verification: verification))
        puts "Generated #{options.fetch(:out)}"
        verification["passed"] ? 0 : 1
      when "compile"
        compile(options)
      when "export-review"
        raise ValidationError, ["--resolutions PATH is required for export-review"] unless options[:resolutions]
        pipeline = Pipeline.new(spec_path: options.fetch(:spec), profile_path: options.fetch(:profile), defaults_path: options.fetch(:defaults), adapter_policy: options.fetch(:idempotency_policy))
        resolutions = YAML.safe_load(File.read(options.fetch(:resolutions), encoding: "UTF-8"), aliases: false) || {}
        entries = resolutions.is_a?(Hash) && resolutions["decisions"].is_a?(Array) ? resolutions["decisions"].map { |item| [item.fetch("decision_id"), item.fetch("value")] } : resolutions.map { |key, value| [key, value] }
        ReviewExporter.write(options.fetch(:review_output), source_document: pipeline.source_document, profile: BaseServiceProfile.load(options.fetch(:profile)), provider_name: pipeline.blueprint.dig("provider", "name"), resolutions: entries)
        puts "Exported confirmed Review decisions to #{options.fetch(:review_output)}"
        0
      else
        puts parser
        0
      end
    rescue Error, ValidationError, BlueprintValidationError => e
      warn e.message
      2
    end

    def self.default_options
      reference_spec = File.exist?("fixtures/novapay_provider_api.yaml") ? "fixtures/novapay_provider_api.yaml" : (Dir.glob("fixtures/*_provider_api.yaml").sort.first || "provider_api.yaml")
      reference_defaults = File.exist?("fixtures/novapay_case_defaults.yml") ? "fixtures/novapay_case_defaults.yml" : (Dir.glob("fixtures/*_case_defaults.yml").sort.first || "case_defaults.yml")
      empty_defaults = File.exist?("fixtures/empty_case_defaults.yml") ? "fixtures/empty_case_defaults.yml" : reference_defaults
      configured_spec = ENV["PROVIDER_SPEC"].to_s.strip
      {
        spec: configured_spec.empty? ? reference_spec : configured_spec,
        profile: "profiles/space_payments_v1.yml",
        defaults: reference_defaults,
        empty_defaults: empty_defaults,
        spec_explicit: false,
        defaults_explicit: false,
        defaults_origin: configured_spec.empty? ? "reference" : "none",
        out: "tmp/generated",
        idempotency_policy: "if_available",
        overrides: nil,
        resolutions: nil,
        review_output: "provider_overrides.yml"
      }
    end

    def self.option_parser(options)
      OptionParser.new do |parser|
        parser.banner = "Usage: provider_compiler COMMAND [options]\nCommands: analyze, inspect, compile, generate, verify, export-review"
        parser.on("--spec PATH", "OpenAPI YAML/JSON") do |value|
          options[:spec] = value
          options[:spec_explicit] = true
          unless options[:defaults_explicit]
            options[:defaults] = options.fetch(:empty_defaults)
            options[:defaults_origin] = "none"
          end
        end
        parser.on("--profile PATH", "BaseServiceProfile YAML") { |value| options[:profile] = value }
        parser.on("--defaults PATH", "case defaults YAML") { |value| options[:defaults] = value; options[:defaults_explicit] = true; options[:defaults_origin] = value }
        parser.on("--out DIR", "output directory") { |value| options[:out] = value }
        parser.on("--output DIR", "output directory (alias for --out)") { |value| options[:out] = value }
        parser.on("--overrides PATH", "versioned HUMAN_CONFIRMED Review override file") { |value| options[:overrides] = value }
        parser.on("--resolutions PATH", "confirmed decision values for export-review") { |value| options[:resolutions] = value }
        parser.on("--review-output PATH", "Review override output file") { |value| options[:review_output] = value }
        parser.on("--always-send-idempotency", "adapter policy; does not change spec_required") { options[:idempotency_policy] = "always" }
      end
    end

    def self.compile(options)
      pipeline = Pipeline.new(spec_path: options.fetch(:spec), profile_path: options.fetch(:profile), defaults_path: options.fetch(:defaults), adapter_policy: options.fetch(:idempotency_policy), overrides_path: options[:overrides])
      output = options.fetch(:out)
      AnalysisArtifactWriter.write(output, pipeline.blueprint, pipeline.manifest)
      generation_blocked = pipeline.blueprint.fetch("decision") != "ACCEPT" || Array(pipeline.blueprint["decisions"]).any? { |item| item["severity"] == "BLOCKING" }

      if generation_blocked
        report = IntegrationReadiness.build(pipeline)
        IntegrationReadiness.write(output, report)
        print_compile_summary(pipeline, report, output, generated_files: %w[provider_blueprint.json review_manifest.json integration_readiness.json INTEGRATION_READINESS.md])
        return 2
      end

      pipeline.validate_blueprint!
      files = DeterministicGenerator.new.generate(pipeline.blueprint, pipeline.manifest, output, examples: pipeline.defaults.examples, spec_document: pipeline.source_document.resolved)
      verification = Verification.new.verify(output)
      report = IntegrationReadiness.build(pipeline, generated: true, verification: verification)
      readiness_files = IntegrationReadiness.write(output, report)
      print_compile_summary(pipeline, report, output, generated_files: files.map { |path| File.basename(path) } + readiness_files.map { |path| File.basename(path) })
      verification["passed"] ? 0 : 1
    end

    def self.print_compile_summary(pipeline, report, output, generated_files:)
      counts = report.dig("decisions", "counts")
      puts "Provider: #{pipeline.blueprint.dig("provider", "name")}"
      puts "Input: #{pipeline.source_document.root_path}"
      puts "Decision: #{pipeline.blueprint.fetch("decision")}"
      puts "Provenance: accepted=#{counts.fetch("accepted_decisions")} spec=#{counts.fetch("spec_evidence_decisions")} builtin_or_generic=#{counts.fetch("builtin_rule_evidence_decisions")} case_default=#{counts.fetch("case_default_decisions")} human_confirmed=#{counts.fetch("human_decisions_supplied")} review_required=#{counts.fetch("review_count")} blocking=#{counts.fetch("blocking_count")}"
      puts "Generated: #{generated_files.join(", ")}"
      puts "Output: #{output}"
      puts "Verification: #{report.dig("verification", "passed") == true ? "PASS" : report.dig("verification", "status") || "NOT_RUN"}"
      puts "Result: #{report.fetch("ready") ? "READY" : "GENERATION_BLOCKED"}"
    end
  end

end
