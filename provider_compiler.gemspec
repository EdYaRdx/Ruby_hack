Gem::Specification.new do |spec|
  spec.name = "provider_compiler"
  spec.version = "0.1.0"
  spec.summary = "Evidence-gated Ruby payment-provider integration compiler"
  spec.authors = ["Hack.Genesis"]
  spec.files = Dir["lib/**/*", "bin/*", "web/**/*", "profiles/**/*", "fixtures/**/*", "spec/**/*", "docs/**/*", "examples/**/*", "research/**/*", "README.md", "THIRD_PARTY.md", "Gemfile", "Gemfile.lock", ".gitattributes"].select { |path| File.file?(path) }
  spec.bindir = "bin"
  spec.executables = ["provider_compiler", "provider_compiler_web"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.0"
  spec.add_runtime_dependency "bigdecimal", ">= 3.1"
  spec.add_runtime_dependency "webrick", "~> 1.9"
  spec.add_development_dependency "rspec", "~> 3.13"
end
