# frozen_string_literal: true

module ProviderCompiler

  class AnalysisArtifactWriter
    RUNTIME_ARTIFACTS = %w[service.rb fixtures.json INTEGRATION.md contract_smoke.rb].freeze

    def self.write(output_dir, blueprint, manifest)
      FileUtils.mkdir_p(output_dir)
      RUNTIME_ARTIFACTS.each do |name|
        path = File.join(output_dir, name)
        File.delete(path) if File.file?(path)
      end
      File.write(File.join(output_dir, "provider_blueprint.json"), Util.pretty_json(blueprint) + "\n", encoding: "UTF-8")
      File.write(File.join(output_dir, "review_manifest.json"), Util.pretty_json(manifest.to_h) + "\n", encoding: "UTF-8")
      ["provider_blueprint.json", "review_manifest.json"].map { |name| File.join(output_dir, name) }
    end
  end

  class Pipeline
    attr_reader :source_document, :facts, :bundle, :blueprint, :manifest, :defaults

    def initialize(spec_path:, profile_path:, defaults_path:, adapter_policy: "if_available", defaults_data: nil)
      @source_document = OpenAPILoader.new(spec_path).load
      OpenAPIValidator.new.validate!(@source_document)
      @facts = FactsBuilder.new.build(@source_document)
      @profile = BaseServiceProfile.load(profile_path)
      @defaults = defaults_data ? CaseDefaults.new(defaults_data) : CaseDefaults.load(defaults_path)
      @bundle = AnalyzerEngine.new(profile: @profile, defaults: @defaults, adapter_policy: adapter_policy).analyze(@facts)
      @blueprint = BlueprintBuilder.new.build(@facts, @profile, @bundle)
      @manifest = ReviewManifest.new(source: @source_document.to_h, decisions: @bundle.decisions, blueprint_status: @blueprint["decision"])
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
        pipeline = Pipeline.new(spec_path: options.fetch(:spec), profile_path: options.fetch(:profile), defaults_path: options.fetch(:defaults), adapter_policy: options.fetch(:idempotency_policy))
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
        pipeline.validate_blueprint!
        DeterministicGenerator.new.generate(pipeline.blueprint, pipeline.manifest, options.fetch(:out), examples: pipeline.defaults.examples, spec_document: pipeline.source_document.resolved)
        puts "Generated #{options.fetch(:out)}"
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
        idempotency_policy: "if_available"
      }
    end

    def self.option_parser(options)
      OptionParser.new do |parser|
        parser.banner = "Usage: provider_compiler COMMAND [options]"
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
        parser.on("--always-send-idempotency", "adapter policy; does not change spec_required") { options[:idempotency_policy] = "always" }
      end
    end
  end

end
