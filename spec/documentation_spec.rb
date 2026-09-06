# frozen_string_literal: true

require "digest"

RSpec.describe "submission documentation" do
  ROOT = File.expand_path("..", __dir__)

  it "keeps the judge-facing documentation tree and canonical example present" do
    paths = %w[
      README.md
      docs/ARCHITECTURE.md
      docs/ORGANIZER_CONTRACT.md
      docs/JURY_FAQ.md
      docs/BENCHMARK.md
      docs/DEMO.md
      docs/DEVELOPMENT.md
      docs/DOCS_POLICY.md
      docs/GLOSSARY.md
      THIRD_PARTY.md
      research/NOVAPAY_SPEC_ONLY_BASELINE.md
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
    expect(File.read(File.join(ROOT, "README.md"))).to include("BEGIN GENERATED: JUDGE_METRICS")
    expect(File.read(File.join(ROOT, "docs", "BENCHMARK.md"))).to include("BEGIN GENERATED: BENCHMARK")
    expect(File.read(File.join(ROOT, "research", "NOVAPAY_SPEC_ONLY_BASELINE.md"))).to include("BEGIN GENERATED: NOVAPAY_SPEC_ONLY_BASELINE")
  end

  it "documents separate decision automation, readiness and safety metrics" do
    readme = File.read(File.join(ROOT, "README.md"), encoding: "UTF-8")
    benchmark = File.read(File.join(ROOT, "docs", "BENCHMARK.md"), encoding: "UTF-8")

    expect(readme).to include("decision_automation_rate")
    expect(readme).to include("fully_auto_ready_rate")
    expect(readme).to include("unsafe_generation_attempts")
    expect(benchmark).to include("decision_automation_rate")
    expect(benchmark).to include("fully_auto_ready_rate")
    expect(benchmark).to include("unsafe_generation_attempts")
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

  it "documents the organizer contract boundary and generated host projection" do
    readme = File.read(File.join(ROOT, "README.md"), encoding: "UTF-8")
    contract = File.read(File.join(ROOT, "docs", "ORGANIZER_CONTRACT.md"), encoding: "UTF-8")
    architecture = File.read(File.join(ROOT, "docs", "ARCHITECTURE.md"), encoding: "UTF-8")
    faq = File.read(File.join(ROOT, "docs", "JURY_FAQ.md"), encoding: "UTF-8")
    integration = File.read(File.join(ROOT, "examples", "novapay", "INTEGRATION.md"), encoding: "UTF-8")

    expect(readme).to include("## Контракт Space Payments", "docs/ORGANIZER_CONTRACT.md")
    expect(contract).to include("operation.payout_requisite", "success(result: { id: provider_operation_id })", "request_method")
    expect(contract).to include("raw body", "amount_limit_exceeded")
    expect(contract).to match(/не\s+пересобирается/)
    expect(architecture).to include("Space Operation", "Host Projection", "request_method != HTTP method != create_request")
    expect(faq).to include("Где сохраняется provider operation id?", "Почему интеграция не всегда полностью автоматическая?")
    expect(integration).to include("Host input и request_method", "result:", "Host action", "Platform code")
  end

  it "keeps current contract wording free from known stale host assumptions" do
    paths = [File.join(ROOT, "README.md"), File.join(ROOT, "docs", "ARCHITECTURE.md"), File.join(ROOT, "docs", "DEMO.md"), File.join(ROOT, "docs", "ORGANIZER_CONTRACT.md"), File.join(ROOT, "examples", "novapay", "INTEGRATION.md")]
    text = paths.map { |path| File.read(path, encoding: "UTF-8") }.join("\n")

    expect(text).not_to include("request_method = create", "request_method: create", "failure(status, code, message)")
    expect(text).not_to match(/daily amount limit|дневн(?:ой|ый) лимит/i)
    expect(text).not_to match(/service (?:saves|сохраняет) provider operation id/i)
    expect(text).to include("Provider operation id сохраняет Space Payments")
  end
end
