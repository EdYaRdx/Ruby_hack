# frozen_string_literal: true

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
end
