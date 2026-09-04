# frozen_string_literal: true

module ProviderCompiler

  class BaseServiceProfile
    attr_reader :data

    def self.load(path)
      data = YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: true) || {}
      new(data)
    rescue Errno::ENOENT => e
      raise Error, "cannot read BaseServiceProfile #{path}: #{e.message}"
    end

    def initialize(data)
      @data = Immutable.deep_freeze(data)
      freeze
    end

    def name
      data["name"]
    end

    def profile_version
      data["profile_version"]
    end

    def required_methods
      Array(data["required_methods"])
    end

    def canonical_operations
      Array(data["canonical_operations"])
    end

    def canonical_operation?(value)
      canonical_operations.include?(value)
    end

    def canonical_amount
      data.fetch("canonical_amount", {})
    end

    def money
      data.fetch("money", {})
    end

    def callback_actions
      data.fetch("callback_actions", {})
    end

    def class_name
      data.fetch("class_name", "Provider::BaseService")
    end

    def to_h
      data
    end
  end

  class CaseDefaults
    attr_reader :data

    def self.load(path)
      data = YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: true) || {}
      new(data)
    rescue Errno::ENOENT => e
      raise Error, "cannot read case defaults #{path}: #{e.message}"
    end

    def initialize(data = {})
      @data = Immutable.deep_freeze(data)
      freeze
    end

    def money
      data.fetch("money", {})
    end

    def statuses
      data.fetch("statuses", {})
    end

    def webhook
      data.fetch("webhook", {})
    end

    def examples
      data.fetch("examples", {})
    end
  end

end
