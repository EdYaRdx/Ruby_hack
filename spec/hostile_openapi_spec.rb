# frozen_string_literal: true

require "tmpdir"

RSpec.describe "hostile OpenAPI boundary" do
  def write_spec(directory, content, name: "provider.yaml")
    path = File.join(directory, name)
    File.write(path, content, encoding: "UTF-8")
    path
  end

  it "rejects malformed roots and non-object OpenAPI documents with diagnostics" do
    Dir.mktmpdir("hostile-openapi") do |directory|
      ["", "not: [valid", "[]", "scalar", "openapi: 3.0.3\npaths: []"].each_with_index do |content, index|
        path = write_spec(directory, content, name: "case-#{index}.yaml")
        expect { ProviderCompiler::Pipeline.new(spec_path: path, profile_path: SpecSupport::PROFILE_PATH, defaults_path: File.join(SpecSupport::ROOT, "fixtures", "empty_case_defaults.yml")) }.to raise_error(ProviderCompiler::Error)
      end
    end
  end

  it "rejects broken, traversal and recursive local references" do
    Dir.mktmpdir("hostile-refs") do |directory|
      outside = File.join(Dir.tmpdir, "provider-compiler-outside-#{Process.pid}.yaml")
      File.write(outside, "Thing: { type: string }\n", encoding: "UTF-8")
      begin
        traversal = <<~YAML
          openapi: 3.0.3
          info: { title: Ref, version: '1' }
          paths:
            /x:
              get:
                responses:
                  '200': { description: ok, content: { application/json: { schema: { $ref: '../provider-compiler-outside-#{Process.pid}.yaml#/Thing' } } } }
        YAML
        expect { ProviderCompiler::OpenAPILoader.new(write_spec(directory, traversal)).load }.to raise_error(ProviderCompiler::RefError, /escapes allowed root/)

        broken = traversal.gsub("../provider-compiler-outside-#{Process.pid}.yaml#/Thing", "missing.yaml#/Thing")
        expect { ProviderCompiler::OpenAPILoader.new(write_spec(directory, broken, name: "broken.yaml")).load }.to raise_error(ProviderCompiler::RefError, /cannot read|unresolved/)

        recursive = <<~YAML
          openapi: 3.0.3
          info: { title: Recursive, version: '1' }
          components:
            schemas:
              Node: { $ref: '#/components/schemas/Node' }
          paths: {}
        YAML
        expect { ProviderCompiler::OpenAPILoader.new(write_spec(directory, recursive, name: "recursive.yaml")).load }.to raise_error(ProviderCompiler::RefError, /recursive/)
      ensure
        File.delete(outside) if File.file?(outside)
      end
    end
  end

  it "rejects a symlink reference that resolves outside the corpus root when supported" do
    Dir.mktmpdir("hostile-symlink") do |directory|
      outside = File.join(Dir.tmpdir, "provider-compiler-symlink-#{Process.pid}.yaml")
      link = File.join(directory, "linked.yaml")
      File.write(outside, "Thing: { type: string }\n", encoding: "UTF-8")
      begin
        begin
          File.symlink(outside, link)
        rescue Errno::EACCES, Errno::EPERM, NotImplementedError
          skip "symlink creation is unavailable in this Windows test environment"
        end
        spec = <<~YAML
          openapi: 3.0.3
          info: { title: Symlink, version: '1' }
          paths:
            /x:
              get:
                responses:
                  '200': { description: ok, content: { application/json: { schema: { $ref: 'linked.yaml#/Thing' } } } }
        YAML
        expect { ProviderCompiler::OpenAPILoader.new(write_spec(directory, spec)).load }.to raise_error(ProviderCompiler::RefError, /symlink|allowed root/)
      ensure
        File.delete(link) if File.symlink?(link)
        File.delete(outside) if File.file?(outside)
      end
    end
  end

  it "blocks invalid or unsafe provider regex before generated runtime" do
    pipeline = ProviderCompiler::Pipeline.new(spec_path: SpecSupport::SPEC_PATH, profile_path: SpecSupport::PROFILE_PATH, defaults_path: SpecSupport::DEFAULTS_PATH)
    blueprint = Marshal.load(Marshal.dump(pipeline.blueprint))
    blueprint["constraints"] = [{ "path" => "request.recipient", "pattern" => "[" }]
    expect { ProviderCompiler::RubyProjection.new(blueprint).render }.to raise_error(ProviderCompiler::Error, /regex is invalid/)
  end

  it "rejects unsafe generated class names and non-HTTP server URLs" do
    pipeline = SpecSupport.pipeline
    unsafe_name = Marshal.load(Marshal.dump(pipeline.blueprint))
    unsafe_name["provider"]["name"] = "123<script>"
    expect { ProviderCompiler::RubyProjection.new(unsafe_name).render }.to raise_error(ProviderCompiler::Error, /class name/)

    unsafe_url = Marshal.load(Marshal.dump(pipeline.blueprint))
    unsafe_url["servers"].first["url"] = "javascript:alert(1)"
    expect { ProviderCompiler::RubyProjection.new(unsafe_url).render }.to raise_error(ProviderCompiler::Error, /HTTP\(S\)/)
  end
end
