Gem::Specification.new do |spec|
  spec.name = "provider_compiler"
  spec.version = "0.1.0"
  spec.summary = "Evidence-gated Ruby payment-provider integration compiler"
  spec.authors = ["Hack.Genesis"]
  spec.homepage = "https://github.com/EdYaRdx/Ruby_hack"
  spec.metadata = {
    "source_code_uri" => "https://github.com/EdYaRdx/Ruby_hack",
    "bug_tracker_uri" => "https://github.com/EdYaRdx/Ruby_hack/issues"
  }
  # The repository keeps research, benchmarks and tests; the release gem keeps
  # only runtime code, bundled demo inputs, user-facing docs and executables.
  spec.files = Dir["lib/**/*", "bin/*", "web/**/*", "profiles/**/*", "fixtures/**/*", "docs/**/*", "README.md", "THIRD_PARTY.md", ".gitattributes"].select { |path| File.file?(path) }
  spec.bindir = "bin"
  spec.executables = ["provider_compiler", "provider_compiler_web"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_runtime_dependency "bigdecimal", ">= 3.1"
  spec.add_runtime_dependency "webrick", "~> 1.9"
  spec.add_development_dependency "rspec", "~> 3.13"
end
