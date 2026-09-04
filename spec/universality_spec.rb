# frozen_string_literal: true

RSpec.describe "generic semantic analyzers" do
  def facts_for(document)
    Dir.mktmpdir("provider-generic") do |directory|
      path = File.join(directory, "api.yml")
      File.write(path, YAML.dump(document))
      source = ProviderCompiler::OpenAPILoader.new(path).load
      return ProviderCompiler::FactsBuilder.new.build(source)
    end
  end

  it "supports header api keys, query api keys, and bearer auth without provider names" do
    header_facts = facts_for("openapi" => "3.0.3", "info" => { "title" => "Header API", "version" => "1" }, "components" => { "securitySchemes" => { "Key" => { "type" => "apiKey", "in" => "header", "name" => "X-Key" } } }, "paths" => {})
    query_facts = facts_for("openapi" => "3.0.3", "info" => { "title" => "Query API", "version" => "1" }, "components" => { "securitySchemes" => { "Key" => { "type" => "apiKey", "in" => "query", "name" => "key" } } }, "paths" => {})
    bearer_facts = facts_for("openapi" => "3.0.3", "info" => { "title" => "Bearer API", "version" => "1" }, "components" => { "securitySchemes" => { "Bearer" => { "type" => "http", "scheme" => "bearer" } } }, "paths" => {})

    expect(ProviderCompiler::AuthAnalyzer.new.analyze(header_facts).section.fetch("strategy")).to include("kind" => "api_key", "transport" => "header")
    expect(ProviderCompiler::AuthAnalyzer.new.analyze(query_facts).section.fetch("strategy")).to include("kind" => "api_key", "transport" => "query")
    expect(ProviderCompiler::AuthAnalyzer.new.analyze(bearer_facts).section.fetch("strategy")).to include("kind" => "bearer", "transport" => "header")
  end

  it "derives money conversion from host/provider units rather than provider identity" do
    profile = ProviderCompiler::BaseServiceProfile.new("canonical_amount" => { "field" => "operation.amount", "currency" => "EUR", "unit" => "major" })
    major_defaults = ProviderCompiler::CaseDefaults.new("money" => { "provider_unit" => "major", "provider_subunit" => "eurocents" })
    minor_defaults = ProviderCompiler::CaseDefaults.new("money" => { "provider_unit" => "minor", "provider_subunit" => "eurocents", "scale" => 100 })
    thousand_defaults = ProviderCompiler::CaseDefaults.new("money" => { "provider_unit" => "minor", "provider_subunit" => "millimes", "scale" => 1000 })
    unknown_defaults = ProviderCompiler::CaseDefaults.new("money" => { "provider_unit" => "minor", "provider_subunit" => "unknown" })
    document = {
      "openapi" => "3.0.3", "info" => { "title" => "Generic Payout API", "version" => "1" },
      "paths" => { "/transfers" => { "post" => { "operationId" => "createTransfer", "requestBody" => { "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "amount" => { "type" => "number", "description" => "amount" }, "currency" => { "enum" => ["EUR"] } } } } } } } } }
    }
    facts = facts_for(document)

    major = ProviderCompiler::MoneyAnalyzer.new(profile, major_defaults).analyze(facts).section
    minor = ProviderCompiler::MoneyAnalyzer.new(profile, minor_defaults).analyze(facts).section
    expect(major.dig("request_conversion", "operation")).to eq("identity")
    expect(major.dig("request_conversion", "scale")).to eq(1)
    thousand = ProviderCompiler::MoneyAnalyzer.new(profile, thousand_defaults).analyze(facts).section
    expect(minor.dig("request_conversion", "operation")).to eq("multiply")
    expect(minor.dig("request_conversion", "direction")).to eq("major_to_minor")
    expect(thousand.dig("request_conversion", "factor")).to eq(1000)
    expect(thousand.dig("response_conversion", "factor")).to eq(0.001)
    expect(thousand.dig("response_conversion", "factor_decimal")).to eq("0.001")
    unresolved = ProviderCompiler::MoneyAnalyzer.new(profile, unknown_defaults).analyze(facts)
    expect(unresolved.section.dig("request_conversion", "status")).to eq("unresolved")
    expect(unresolved.decisions.first.to_h).to include("outcome" => "REVIEW_REQUIRED", "severity" => "BLOCKING")
  end
end
