# frozen_string_literal: true

module ProviderCompiler

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
      case command
      when "analyze", "inspect", "generate", "verify"
        if command == "verify"
          result = Verification.new.verify(options.fetch(:out))
          puts JSON.pretty_generate(result)
          return result["passed"] ? 0 : 1
        end
        pipeline = Pipeline.new(spec_path: options.fetch(:spec), profile_path: options.fetch(:profile), defaults_path: options.fetch(:defaults), adapter_policy: options.fetch(:idempotency_policy))
        if command == "inspect"
          puts JSON.pretty_generate(pipeline.manifest.to_h.fetch("summary"))
          return 0
        end
        if command == "analyze"
          DeterministicGenerator.new.generate(pipeline.blueprint, pipeline.manifest, options.fetch(:out), examples: pipeline.defaults.examples)
          puts JSON.pretty_generate(pipeline.manifest.to_h.fetch("summary"))
          return 0
        end
        pipeline.validate_blueprint!
        DeterministicGenerator.new.generate(pipeline.blueprint, pipeline.manifest, options.fetch(:out), examples: pipeline.defaults.examples)
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
      configured_spec = ENV["PROVIDER_SPEC"].to_s.strip
      {
        spec: configured_spec.empty? ? reference_spec : configured_spec,
        profile: "profiles/space_payments_v1.yml",
        defaults: reference_defaults,
        out: "tmp/generated",
        idempotency_policy: "if_available"
      }
    end

    def self.option_parser(options)
      OptionParser.new do |parser|
        parser.banner = "Usage: provider_compiler COMMAND [options]"
        parser.on("--spec PATH", "OpenAPI YAML/JSON") { |value| options[:spec] = value }
        parser.on("--profile PATH", "BaseServiceProfile YAML") { |value| options[:profile] = value }
        parser.on("--defaults PATH", "case defaults YAML") { |value| options[:defaults] = value }
        parser.on("--out DIR", "output directory") { |value| options[:out] = value }
        parser.on("--output DIR", "output directory (alias for --out)") { |value| options[:out] = value }
        parser.on("--always-send-idempotency", "adapter policy; does not change spec_required") { options[:idempotency_policy] = "always" }
      end
    end
  end

end
