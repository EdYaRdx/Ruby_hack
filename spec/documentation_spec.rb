# frozen_string_literal: true

require "digest"

RSpec.describe "submission documentation" do
  ROOT = File.expand_path("..", __dir__)

  it "keeps the judge-facing documentation tree and canonical example present" do
    paths = %w[
      README.md
      docs/ARCHITECTURE.md
      docs/BENCHMARK.md
      docs/DEMO.md
      docs/DEVELOPMENT.md
      docs/DOCS_POLICY.md
      docs/GLOSSARY.md
      THIRD_PARTY.md
      examples/novapay/provider_api.yaml
      examples/novapay/provider_blueprint.json
      examples/novapay/review_manifest.json
      examples/novapay/service.rb
      examples/novapay/fixtures.json
      examples/novapay/INTEGRATION.md
      examples/novapay/contract_smoke.rb
    ]

    expect(paths).to all(satisfy { |path| File.file?(File.join(ROOT, path)) })
  end

  it "contains generated markers for dynamic status" do
    expect(File.read(File.join(ROOT, "README.md"))).to include("BEGIN GENERATED: PROJECT_STATUS")
    expect(File.read(File.join(ROOT, "README.md"))).to include("BEGIN GENERATED: CAPABILITIES")
    expect(File.read(File.join(ROOT, "docs", "BENCHMARK.md"))).to include("BEGIN GENERATED: BENCHMARK")
  end

  it "does not leak local Windows paths or attachment locations" do
    paths = [File.join(ROOT, "README.md"), File.join(ROOT, "THIRD_PARTY.md")] + Dir[File.join(ROOT, "docs", "**", "*.md")] + [File.join(ROOT, "examples", "novapay", "INTEGRATION.md")]
    text = paths.map { |path| File.read(path, encoding: "UTF-8") }.join("\n")
    expect(text).not_to match(/C:[\\\\\/]+Users[\\\\\/]/i)
    expect(text).not_to include(".codex/attachments")
  end

  it "keeps the live commands and URL documented" do
    paths = [
      File.join(ROOT, "README.md"),
      File.join(ROOT, "docs", "DEMO.md"),
      File.join(ROOT, "docs", "DEVELOPMENT.md")
    ]
    text = paths.map { |path| File.read(path, encoding: "UTF-8") }.join("\n")

    expect(text).to include("bundle exec ruby bin/provider_compiler_web")
    expect(text).to include("http://127.0.0.1:4567")
    expect(text).to include("ruby bin/provider_compiler inspect")
    expect(text).to include("ruby bin/provider_compiler generate")
    expect(text).to include("ruby bin/provider_compiler verify")
  end

  it "resolves every relative Markdown link in the repository" do
    markdown_paths = Dir[File.join(ROOT, "**", "*.md")].reject do |path|
      path.split(File::SEPARATOR).include?(".git") || path.split(File::SEPARATOR).include?("tmp")
    end

    broken = markdown_paths.flat_map do |path|
      source = File.read(path, encoding: "UTF-8")
      source.scan(/\[[^\]]+\]\((?:<([^>]+)>|([^\s)]+))(?:\s+["'][^)]*["'])?\)/).filter_map do |match|
        target = match[0] || match[1]
        next if target.match?(/\A(?:https?:|mailto:)/i) || target.start_with?("#")

        local_target = target.split("#", 2).first
        next if local_target.empty?

        resolved = File.expand_path(local_target, File.dirname(path))
        next if File.file?(resolved) || Dir.exist?(resolved)

        "#{path.sub(ROOT + File::SEPARATOR, "")}: #{target}"
      end
    end

    expect(broken).to eq([])
  end

  it "keeps current judge-facing docs free from accidental placeholders and inference-service claims" do
    paths = [File.join(ROOT, "README.md"), File.join(ROOT, "THIRD_PARTY.md")] +
      Dir[File.join(ROOT, "docs", "**", "*.md")] +
      [File.join(ROOT, "examples", "novapay", "INTEGRATION.md")]
    text = paths.map { |path| File.read(path, encoding: "UTF-8") }.join("\n")

    expect(text).not_to match(/\b(?:TODO|TBD|PLACEHOLDER|FIXME)\b/i)
    expect(text).not_to match(/\b(?:LLM|GPT|embedding|AI semantic|proprietary AI)\b/i)
  end

  it "keeps the official NovaPay fixture hash documented" do
    fixture = File.join(ROOT, "fixtures", "novapay_provider_api.yaml")
    reference = File.read(File.join(ROOT, "research", "REFERENCE_GROUND_TRUTH.md"), encoding: "UTF-8")

    expect(reference).to include(Digest::SHA256.file(fixture).hexdigest.upcase)
  end
end
