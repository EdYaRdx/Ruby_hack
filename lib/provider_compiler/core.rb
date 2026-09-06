# frozen_string_literal: true

require "bigdecimal"
require "digest"
require "erb"
require "fileutils"
require "json"
require "openssl"
require "open3"
require "optparse"
require "rbconfig"
require "time"
require "yaml"

module ProviderCompiler
  VERSION = "0.1.0"

  module Immutable
    module_function

    def deep_freeze(value)
      case value
      when Hash
        value.each { |key, item| deep_freeze(key); deep_freeze(item) }
      when Array
        value.each { |item| deep_freeze(item) }
      end
      value.freeze
    end
  end

  module Util
    module_function

    def deep_dup(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), result| result[deep_dup(key)] = deep_dup(item) }
      when Array
        value.map { |item| deep_dup(item) }
      else
        value
      end
    end

    def slug(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").sub(/-api\z/, "").split("-").first.to_s
    end

    def camel(value)
      value.to_s.split(/[^a-zA-Z0-9]+/).reject(&:empty?).map(&:capitalize).join
    end

    def relative_path(path, root_dir)
      path = File.expand_path(path)
      root_dir = File.expand_path(root_dir)
      relative = path.start_with?("#{root_dir}#{File::SEPARATOR}") ? path.delete_prefix("#{root_dir}#{File::SEPARATOR}") : path
      relative.tr("\\", "/")
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
          original_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
          result[key] = canonicalize(value[original_key])
        end
      when Array
        value.map { |item| canonicalize(item) }
      else
        value
      end
    end

    # JSON's default pretty printer changed its rendering of empty objects and
    # arrays between Ruby versions. Keep committed artifacts byte-stable on
    # the Ruby 3.3 CI runner and on newer local Rubies.
    def pretty_json(value)
      JSON.pretty_generate(value).gsub(/\{\n\s*\}/, "{}").gsub(/\[\n\s*\]/, "[]")
    end

    def pointer_get(document, fragment)
      return document if fragment.nil? || fragment.empty? || fragment == "#"

      pointer = fragment.start_with?("#") ? fragment.delete_prefix("#") : fragment
      parts = pointer.split("/").drop(1).map { |part| part.gsub("~1", "/").gsub("~0", "~") }
      parts.reduce(document) do |current, part|
        case current
        when Hash
          current.fetch(part)
        when Array
          current.fetch(Integer(part))
        else
          raise KeyError, "cannot follow JSON pointer #{fragment.inspect}"
        end
      end
    end

    def read(object, key)
      return nil unless object

      object[key] || object[key.to_s]
    end

    def blank?(value)
      value.nil? || value.to_s.empty?
    end
  end

  class Error < StandardError; end
  class RefError < Error; end
  class ValidationError < Error
    attr_reader :issues

    def initialize(issues)
      @issues = issues.freeze
      super(issues.join("; "))
    end
  end

  class BlueprintValidationError < ValidationError; end

  class RefResolver
    POLICY_VERSION = 2
    MAX_FILE_BYTES = 10 * 1024 * 1024
    MAX_RESOLUTION_NODES = 100_000
    MAX_RESOLUTION_DEPTH = 64
    attr_reader :resolved_refs, :loaded_files

    def initialize(root_path)
      @root_path = File.realpath(root_path)
      @root_dir = File.dirname(@root_path)
      @root_real_dir = File.realpath(@root_dir)
      @documents = {}
      @resolved_refs = []
      @loaded_files = {}
      @resolution_nodes = 0
    end

    def resolve(root_document)
      @documents[@root_path] = root_document
      remember_file(@root_path)
      resolve_node(root_document, current_path: @root_path, stack: [], depth: 0)
    end

    private

    def resolve_node(node, current_path:, stack:, depth:)
      @resolution_nodes += 1
      raise RefError, "OpenAPI reference graph is too large" if @resolution_nodes > MAX_RESOLUTION_NODES
      raise RefError, "OpenAPI reference graph is too deep" if depth > MAX_RESOLUTION_DEPTH

      case node
      when Hash
        if node.key?("$ref")
          resolved = resolve_ref(node.fetch("$ref"), current_path: current_path, stack: stack, depth: depth)
          extras = node.reject { |key, _| key == "$ref" }
          extras.empty? ? resolved : deep_merge(resolved, resolve_node(extras, current_path: current_path, stack: stack, depth: depth + 1))
        else
          node.each_with_object({}) do |(key, value), result|
            result[key] = resolve_node(value, current_path: current_path, stack: stack, depth: depth + 1)
          end
        end
      when Array
        node.map { |item| resolve_node(item, current_path: current_path, stack: stack, depth: depth + 1) }
      else
        node
      end
    end

    def resolve_ref(reference, current_path:, stack:, depth:)
      target_path, fragment = split_reference(reference, current_path)
      key = "#{target_path}##{fragment}"
      raise RefError, "recursive $ref detected at #{key}" if stack.include?(key)

      @resolved_refs << {
        "source_file" => Util.relative_path(current_path, @root_dir),
        "ref" => reference,
        "target_file" => Util.relative_path(target_path, @root_dir),
        "fragment" => fragment
      }
      target_document = load_document(target_path)
      target = Util.pointer_get(target_document, fragment)
      resolve_node(Util.deep_dup(target), current_path: target_path, stack: stack + [key], depth: depth + 1)
    rescue KeyError, IndexError => e
      raise RefError, "unresolved $ref #{reference.inspect}: #{e.message}"
    end

    def split_reference(reference, current_path)
      reference = reference.to_s
      if reference.match?(%r{\A[a-z][a-z0-9+.-]*://}i) || reference.start_with?("//")
        raise RefError, "remote $ref is not allowed: #{reference}"
      end

      external, fragment = reference.split("#", 2)
      target_path = if external.nil? || external.empty?
                      current_path
                    else
                      File.expand_path(external, File.dirname(current_path))
                    end
      root_prefix = "#{@root_real_dir}#{File::SEPARATOR}"
      unless target_path == @root_real_dir || target_path.start_with?(root_prefix)
        raise RefError, "$ref escapes allowed root: #{reference}"
      end
      if File.exist?(target_path)
        target_path = File.realpath(target_path)
        unless target_path == @root_real_dir || target_path.start_with?(root_prefix)
          raise RefError, "$ref escapes allowed root through a symlink: #{reference}"
        end
      end
      [target_path, fragment ? "##{fragment}" : ""]
    end

    def load_document(path)
      return @documents.fetch(path) if @documents.key?(path)

      @documents[path] = parse_file(path)
      remember_file(path)
      @documents.fetch(path)
    end

    def parse_file(path)
      size = File.size(path)
      raise RefError, "ref document exceeds #{MAX_FILE_BYTES} bytes: #{path}" if size > MAX_FILE_BYTES

      content = File.read(path, encoding: "UTF-8")
      if File.extname(path).downcase == ".json"
        JSON.parse(content)
      else
        YAML.safe_load(content, aliases: true) || {}
      end
    rescue Errno::ENOENT => e
      raise RefError, "cannot read $ref document #{path}: #{e.message}"
    rescue JSON::ParserError, Psych::Exception => e
      raise RefError, "cannot parse $ref document #{path}: #{e.message}"
    end

    def remember_file(path)
      canonical_path = File.realpath(path)
      @loaded_files[Util.relative_path(canonical_path, @root_real_dir)] = Digest::SHA256.hexdigest(File.binread(canonical_path))
    end

    def deep_merge(left, right)
      left.merge(right) do |_key, old_value, new_value|
        old_value.is_a?(Hash) && new_value.is_a?(Hash) ? deep_merge(old_value, new_value) : new_value
      end
    end
  end

  class SourceDocument
    attr_reader :root_path, :raw, :resolved, :resolved_refs, :loaded_files, :fingerprint

    def initialize(root_path:, raw:, resolved:, resolved_refs:, loaded_files:)
      @root_path = File.expand_path(root_path)
      @raw = Immutable.deep_freeze(raw)
      @resolved = Immutable.deep_freeze(resolved)
      @resolved_refs = Immutable.deep_freeze(resolved_refs.uniq { |item| JSON.generate(item) }.sort_by { |item| JSON.generate(item) })
      @loaded_files = Immutable.deep_freeze(loaded_files)
      @fingerprint = "sha256:#{Fingerprint.compute(@root_path, @resolved, @resolved_refs, @loaded_files)}"
      freeze
    end

    def root_sha256
      @loaded_files.fetch(File.basename(@root_path)).upcase
    end

    def to_h
      {
        "spec_fingerprint" => @fingerprint,
        "root_document_sha256" => root_sha256,
        "fingerprint_inputs" => {
          "root_document" => File.basename(@root_path),
          "resolved_local_ref_closure" => @resolved_refs,
          "resolved_files" => @loaded_files,
          "resolver_policy_version" => RefResolver::POLICY_VERSION
        }
      }
    end
  end

  module Fingerprint
    module_function

    def compute(root_path, resolved, refs, loaded_files)
      payload = {
        "root_document" => File.basename(root_path),
        "resolved_files" => loaded_files,
        "resolved_local_ref_closure" => refs,
        "resolver_policy_version" => RefResolver::POLICY_VERSION,
        "resolved_document" => Util.canonicalize(resolved)
      }
      Digest::SHA256.hexdigest(JSON.generate(Util.canonicalize(payload)))
    end
  end

  class OpenAPILoader
    def initialize(path)
      @path = File.expand_path(path)
    end

    def load
      raw = parse_file(@path)
      resolver = RefResolver.new(@path)
      resolved = resolver.resolve(raw)
      SourceDocument.new(
        root_path: @path,
        raw: raw,
        resolved: resolved,
        resolved_refs: resolver.resolved_refs,
        loaded_files: resolver.loaded_files
      )
    rescue Errno::ENOENT => e
      raise Error, "cannot read OpenAPI input #{@path}: #{e.message}"
    rescue JSON::ParserError, Psych::Exception => e
      raise Error, "cannot parse OpenAPI input #{@path}: #{e.message}"
    end

    private

    def parse_file(path)
      size = File.size(path)
      raise Error, "OpenAPI input exceeds #{RefResolver::MAX_FILE_BYTES} bytes" if size > RefResolver::MAX_FILE_BYTES

      content = File.read(path, encoding: "UTF-8")
      if File.extname(path).downcase == ".json"
        JSON.parse(content)
      else
        YAML.safe_load(content, aliases: true) || {}
      end
    end
  end

  class OpenAPIValidator
    METHODS = %w[get post put patch delete options head trace].freeze

    def validate!(source_document)
      document = source_document.resolved
      issues = []
      unless document.is_a?(Hash)
        raise ValidationError, ["OpenAPI document must be an object"]
      end
      issues << "openapi must be a 3.x string" unless document["openapi"].to_s.start_with?("3.")
      issues << "info.title is required" unless document.dig("info", "title").is_a?(String)
      issues << "info.version is required" unless document.dig("info", "version").is_a?(String)
      paths = document["paths"]
      issues << "paths must be an object" unless paths.is_a?(Hash)
      if paths.is_a?(Hash)
        paths.each do |path, item|
          issues << "path must start with /: #{path}" unless path.to_s.start_with?("/")
          next unless item.is_a?(Hash)

          item.each do |method, operation|
            next if method == "parameters"
            next unless METHODS.include?(method.to_s.downcase)
            issues << "operation #{method.upcase} #{path} must be an object" unless operation.is_a?(Hash)
          end
        end
      end
      raise ValidationError, issues unless issues.empty?

      true
    end
  end

  class OperationFact
    attr_reader :data

    def initialize(data)
      @data = Immutable.deep_freeze(data)
      freeze
    end

    def [](key)
      @data[key.to_s] || @data[key.to_sym]
    end

    def dig(*keys)
      keys.reduce(@data) do |current, key|
        break nil unless current.respond_to?(:[])
        current[key.to_s] || current[key.to_sym]
      end
    end

    def to_h
      @data
    end
  end

  class FactsIR
    attr_reader :source, :operations, :components, :info, :servers, :text_facts

    def initialize(source:, operations:, components:, info:, servers:, text_facts:)
      @source = source
      @operations = Immutable.deep_freeze(operations)
      @components = Immutable.deep_freeze(components)
      @info = Immutable.deep_freeze(info)
      @servers = Immutable.deep_freeze(servers)
      @text_facts = Immutable.deep_freeze(text_facts)
      freeze
    end

    def schemas
      @components.fetch("schemas", {})
    end

    def security_schemes
      @components.fetch("securitySchemes", {})
    end

    def schema(name)
      schemas[name]
    end

    def to_h
      {
        "source" => @source.to_h,
        "info" => @info,
        "servers" => @servers,
        "operations" => @operations.map(&:to_h),
        "components" => @components,
        "text_facts" => @text_facts
      }
    end
  end

  class FactsBuilder
    METHODS = %w[get post put patch delete options head trace].freeze

    def build(source_document)
      document = source_document.resolved
      operations = []
      document.fetch("paths", {}).each do |path, path_item|
        next unless path_item.is_a?(Hash)

        METHODS.each do |method|
          operation = path_item[method]
          next unless operation.is_a?(Hash)

          operations << operation_fact(path: path, method: method, path_item: path_item, operation: operation)
        end
      end

      document.fetch("paths", {}).each do |path, path_item|
        next unless path_item.is_a?(Hash)

        METHODS.each do |method|
          parent = path_item[method]
          next unless parent.is_a?(Hash) && parent["callbacks"].is_a?(Hash)

          parent.fetch("callbacks").each do |callback_name, callback_definition|
            next unless callback_definition.is_a?(Hash)

            callback_definition.each do |expression, callback_path_item|
              next unless callback_path_item.is_a?(Hash)

              METHODS.each do |callback_method|
                callback_operation = callback_path_item[callback_method]
                next unless callback_operation.is_a?(Hash)

                operations << operation_fact(
                  path: expression,
                  method: callback_method,
                  path_item: callback_path_item,
                  operation: callback_operation,
                  source_kind: "webhook",
                  source_name: callback_name
                )
              end
            end
          end
        end
      end

      document.fetch("webhooks", {}).each do |webhook_name, path_item|
        next unless path_item.is_a?(Hash)

        METHODS.each do |method|
          operation = path_item[method]
          next unless operation.is_a?(Hash)

          operations << operation_fact(path: webhook_name, method: method, path_item: path_item, operation: operation, source_kind: "webhook", source_name: webhook_name)
        end
      end

      FactsIR.new(
        source: source_document,
        operations: operations,
        components: document.fetch("components", {}),
        info: document.fetch("info", {}),
        servers: Array(document["servers"]),
        text_facts: collect_text_facts(document)
      )
    end

    private

    def operation_fact(path:, method:, path_item:, operation:, source_kind: nil, source_name: nil)
      data = {
        "path" => path,
        "method" => method.upcase,
        "operation_id" => operation["operationId"],
        "summary" => operation["summary"],
        "description" => operation["description"],
        "tags" => Array(operation["tags"]),
        "parameters" => Array(path_item["parameters"]) + Array(operation["parameters"]),
        "request_body" => operation["requestBody"],
        "responses" => operation.fetch("responses", {}),
        "success_statuses" => operation.fetch("responses", {}).keys.map(&:to_s).select { |status| status.match?(/\A2\d\d\z/) }.sort,
        "security" => operation["security"],
        "callbacks" => operation["callbacks"],
        "raw" => operation
      }
      data["source_kind"] = source_kind if source_kind
      data["source_name"] = source_name if source_name
      OperationFact.new(data)
    end

    def collect_text_facts(document)
      facts = []
      walk(document, "", facts)
      facts
    end

    def walk(node, pointer, facts)
      case node
      when Hash
        node.each do |key, value|
          child = "#{pointer}/#{key.to_s.gsub("~", "~0").gsub("/", "~1")}"
          if %w[description summary].include?(key.to_s) && value.is_a?(String)
            facts << { "pointer" => child, "kind" => key.to_s, "text" => value }
          end
          walk(value, child, facts)
        end
      when Array
        node.each_with_index { |value, index| walk(value, "#{pointer}/#{index}", facts) }
      end
    end
  end

end
