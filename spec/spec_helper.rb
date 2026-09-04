# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "rbconfig"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "provider_compiler"
require_relative "support/base_service_stub"

RSpec.configure do |config|
  config.order = :defined
end

module SpecSupport
  module_function

  ROOT = File.expand_path("..", __dir__)
  SPEC_PATH = File.join(ROOT, "fixtures", "novapay_provider_api.yaml")
  PROFILE_PATH = File.join(ROOT, "profiles", "space_payments_v1.yml")
  DEFAULTS_PATH = File.join(ROOT, "fixtures", "novapay_case_defaults.yml")
  BIN_PATH = File.join(ROOT, "bin", "provider_compiler")

  def pipeline(adapter_policy: "if_available")
    ProviderCompiler::Pipeline.new(spec_path: SPEC_PATH, profile_path: PROFILE_PATH, defaults_path: DEFAULTS_PATH, adapter_policy: adapter_policy)
  end
end
