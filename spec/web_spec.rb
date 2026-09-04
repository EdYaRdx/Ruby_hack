# frozen_string_literal: true

require "uri"
require "webrick"
require "provider_compiler/web"

RSpec.describe ProviderCompiler::Web::Application do
  class FakeRequest
    attr_reader :request_method, :path, :body, :header

    def initialize(method, path, body: "", content_type: "application/x-www-form-urlencoded")
      @request_method = method
      @path = path.split("?", 2).first
      @query_string = path.split("?", 2).last if path.include?("?")
      @body = body
      @header = { "content-type" => [content_type] }
    end

    def query
      WEBrick::HTTPUtils.parse_query(@query_string.to_s)
    end
  end

  class FakeResponse
    attr_accessor :status, :body
    attr_reader :headers

    def initialize
      @status = 200
      @body = ""
      @headers = {}
    end

    def [](name)
      @headers[name]
    end

    def []=(name, value)
      @headers[name] = value
    end
  end

  let(:store) { ProviderCompiler::Web::WorkspaceStore.new }
  let(:app) { described_class.new(store: store) }

  after do
    store.cleanup
  end

  def call(method, path, body: "", content_type: "application/x-www-form-urlencoded")
    request = FakeRequest.new(method, path, body: body, content_type: content_type)
    response = FakeResponse.new
    app.call(request, response)
    response
  end

  def workspace_id(response)
    response.headers.fetch("Location")[%r{/workspace/([a-f0-9]+)/}, 1]
  end

  def multipart(fields, file_name: nil, file_data: nil)
    boundary = "----provider-compiler-test"
    parts = fields.map do |name, value|
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
    end
    if file_name
      parts << "--#{boundary}\r\nContent-Disposition: form-data; name=\"spec_file\"; filename=\"#{file_name}\"\r\nContent-Type: application/yaml\r\n\r\n#{file_data}\r\n"
    end
    [parts.join + "--#{boundary}--\r\n", "multipart/form-data; boundary=#{boundary}"]
  end

  it "renders the Figma-shaped upload workbench" do
    response = call("GET", "/")

    expect(response.status).to eq(200)
    expect(response.body).to include("Рабочая панель интеграций", "Анализировать спецификацию", "1. Спецификация", "5. Генерация")
    expect(response.body).not_to include("Analyze specification", "Load NovaPay example")
  end

  it "runs the NovaPay demo through analysis and exposes evidence" do
    response = call("POST", "/demo", body: "demo=novapay")
    id = workspace_id(response)
    analysis = call("GET", "/workspace/#{id}/analysis")

    expect(response.status).to eq(303)
    expect(analysis.status).to eq(200)
    expect(analysis.body).to include("getPayoutStatus", "major RUB", "minor RUB", "Почему принято это решение?", "Идемпотентность", "Сопоставление полей", "Ограничения", "Ошибки", "Источник", "Факт", "Расположение", "Дополнительная операция", "EXTRA_OPERATION")
    expect(store.fetch(id).blueprint.fetch("decision")).to eq("ACCEPT")
  end

  it "keeps an ambiguous provider fail-closed in Review and Generate" do
    response = call("POST", "/demo", body: "demo=ambiguous")
    id = workspace_id(response)
    review = call("GET", "/workspace/#{id}/review")
    expect(call("GET", "/workspace/#{id}/analysis").body).not_to include(">UNKNOWN<")
    generate = call("GET", "/workspace/#{id}/generate")
    blocked_post = call("POST", "/workspace/#{id}/generate")

    expect(review.body).to include("Генерация заблокирована", "Известно", "Не хватает данных", "Предлагаемый вариант", "Основания", "Почему генерация заблокирована?", "Подтвердить вариант", "Изменить решение")
    expect(review.body).not_to include(">Generation blocked<", ">Confirm<", ">Edit<")
    expect(generate.body).to include("Генерация недоступна", "Открыть проверку")
    expect(blocked_post.status).to eq(422)
    expect(blocked_post.body).to include("Генерация недоступна", "Технические подробности")
    expect(store.fetch(id).generated?).to be(false)
  end

  it "makes the resolved Review screen actionable" do
    response = call("POST", "/demo", body: "demo=novapay")
    id = workspace_id(response)
    review = call("GET", "/workspace/#{id}/review")

    expect(review.body).to include("Проверка не требуется", "14 решений принято", "0 требуют проверки", "0 блокирующих", "Перейти к предпросмотру", "Перейти к генерации")
    expect(review.body).not_to include("Нет unresolved decisions")
  end

  it "uses generated runtime semantics for request, response and webhook preview" do
    response = call("POST", "/demo", body: "demo=novapay")
    id = workspace_id(response)
    workspace = store.fetch(id)

    request_preview = call("POST", "/workspace/#{id}/preview", body: "kind=request&amount=1500.50")
    response_preview = call("POST", "/workspace/#{id}/preview", body: "kind=response")
    webhook_preview = call("POST", "/workspace/#{id}/preview", body: "kind=webhook")

    expect(request_preview.status).to eq(303)
    expect(response_preview.status).to eq(303)
    expect(webhook_preview.status).to eq(303)
    expect(workspace.preview_results.dig("request", "provider_request", "body", "amount")).to eq(150_050)
    expect(workspace.preview_results.dig("response", "host_result", "amount").to_f).to eq(1500.5)
    expect(workspace.preview_results.dig("response", "host_result", "status")).to eq("approved")
    expect(workspace.preview_results.dig("webhook", "result", "action")).to eq("approve_operation")
    expect(call("GET", "/workspace/#{id}/preview?kind=webhook").body).to include("терминальное событие: да")

    expect(call("GET", "/workspace/#{id}/preview?kind=request").body).to include("150050")
    expect(call("GET", "/workspace/#{id}/preview?kind=response").body).to include("1500.50", "approved")
    expect(call("GET", "/workspace/#{id}/preview?kind=webhook").body).to include("approve_operation", "HMAC-SHA256")
  end

  it "shows a distinct empty preview state before runtime execution" do
    response = call("POST", "/demo", body: "demo=novapay")
    id = workspace_id(response)
    request_page = call("GET", "/workspace/#{id}/preview?kind=request")
    response_page = call("GET", "/workspace/#{id}/preview?kind=response")
    webhook_page = call("GET", "/workspace/#{id}/preview?kind=webhook")

    expect(request_page.body).to include("Ожидает запуска", "Нажмите «Запустить предпросмотр»")
    expect(request_page.body).not_to include("150050")
    expect(response_page.body).to include("Ожидает запуска", "Запустить предпросмотр")
    expect(response_page.body).not_to include(">completed<", ">approved<")
    expect(webhook_page.body).to include("Ожидает запуска", "Запустить предпросмотр")
    expect(webhook_page.body).not_to include(">approve_operation<")
  end

  it "keeps Aurora provider identifiers while using Russian presentation labels" do
    response = call("POST", "/demo", body: "demo=aurora")
    id = workspace_id(response)
    analysis = call("GET", "/workspace/#{id}/analysis")
    expect(analysis.body).not_to include(">UNKNOWN<")

    expect(analysis.body).to include("Операции", "Параметры интеграции", "Авторизация", "Деньги", "Сопоставление статусов", "create_request", "fetch_status", "/transfers")
    expect(analysis.body).not_to include("Integration facts", "Status mapping", "Generate integration")
  end

  it "shows pre-generation checks as not run and exposes Russian status terminology" do
    response = call("POST", "/demo", body: "demo=novapay")
    id = workspace_id(response)
    page = call("GET", "/workspace/#{id}/generate")

    expect(page.body).to include("Готово к генерации", "ГОТОВО К ГЕНЕРАЦИИ", "Сгенерировать интеграцию", "Сгенерированный Ruby", "Runtime smoke", "НЕ ЗАПУЩЕНО")
    expect(page.body).not_to include("ПРОВЕРЕНО", "READY", "VERIFIED")
  end

  it "generates and verifies the real artifact set" do
    response = call("POST", "/demo", body: "demo=novapay")
    id = workspace_id(response)
    generated = call("POST", "/workspace/#{id}/generate")
    page = call("GET", "/workspace/#{id}/generate")
    artifact = call("GET", "/workspace/#{id}/artifact?name=service.rb")

    expect(generated.status).to eq(303)
    expect(page.body).to include("ПРОВЕРЕНО", "Интеграция сгенерирована", "service.rb", "Runtime smoke", "ПРОЙДЕНО")
    expect(artifact.body).to include("class NovapayService")
    expect(store.fetch(id).verification.dig("syntax", 0, "passed")).to be(true)
  end

  it "does not present READY or VERIFIED when a real verification result fails" do
    response = call("POST", "/demo", body: "demo=novapay")
    id = workspace_id(response)
    workspace = store.fetch(id)
    workspace.generate!
    workspace.verification["passed"] = false
    workspace.verification["syntax"][0]["passed"] = false
    page = call("GET", "/workspace/#{id}/generate")

    expect(page.body).to include("ПРОВЕРКА НЕ ПРОЙДЕНА", "ОШИБКА")
    expect(page.body).not_to include("status-pill ready\">ПРОВЕРЕНО", "status-pill ready\">ГОТОВО К ГЕНЕРАЦИИ")
  end

  it "localizes controlled upload errors and keeps code scrolling inside viewers" do
    missing_upload = call("POST", "/analyze", body: "")
    css = call("GET", "/static/app.css")
    remote_ref = <<~YAML
      openapi: "3.0.3"
      info:
        title: Remote
        version: "1"
      paths:
        /payouts:
          post:
            operationId: createPayout
            requestBody:
              content:
                application/json:
                  schema:
                    $ref: "https://example.test/schema.yml#/Payout"
    YAML
    body, content_type = multipart({}, file_name: "remote.yaml", file_data: remote_ref)
    remote_response = call("POST", "/analyze", body: body, content_type: content_type)

    expect(missing_upload.status).to eq(422)
    expect(missing_upload.body).to include("Выберите файл OpenAPI", "Технические подробности")
    expect(remote_response.status).to eq(422)
    expect(remote_response.body).to include("Удалённые $ref не поддерживаются")
    expect(css.body).to include("body {", "overflow-x: hidden", ".code-block", "width: 100%", "overflow-x: auto", "white-space: pre", ".artifact-viewer")
  end

  it "accepts local multipart uploads and rejects unsupported extensions" do
    source = File.binread(File.join(ProviderCompiler::Web::ROOT, "fixtures", "novapay_provider_api.yaml"))
    body, content_type = multipart({}, file_name: "provider_api.yaml", file_data: source)
    response = call("POST", "/analyze", body: body, content_type: content_type)
    id = workspace_id(response)

    expect(response.status).to eq(303)
    expect(store.fetch(id).blueprint.fetch("decision")).to eq("ACCEPT")
    expect { store.create_upload(filename: "provider_api.txt", content: source) }.to raise_error(ProviderCompiler::ValidationError)
  end

  it "renders preview failures as controlled Russian errors" do
    response = call("POST", "/demo", body: "demo=novapay")
    id = workspace_id(response)
    failed = call("POST", "/workspace/#{id}/preview", body: "kind=request&amount=not-a-number")

    expect(failed.status).to eq(500)
    expect(failed.body).to include("Не удалось выполнить операцию", "Технические подробности")
    expect(failed.body).not_to include("backtrace", "stack trace")
  end
end
