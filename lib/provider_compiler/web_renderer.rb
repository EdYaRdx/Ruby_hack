# frozen_string_literal: true

module ProviderCompiler
  module Web
    class Renderer
      NAV_ITEMS = [
        ["spec", "1. Спецификация", "upload"],
        ["analysis", "2. Анализ", "analysis"],
        ["review", "3. Проверка", "review"],
        ["preview", "4. Предпросмотр", "preview"],
        ["generate", "5. Генерация", "generate"]
      ].freeze

      STATUS_LABELS = {
        "ACCEPT" => "ПРИНЯТО",
        "REVIEW_REQUIRED" => "ТРЕБУЕТ ПРОВЕРКИ",
        "REVIEW REQUIRED" => "ТРЕБУЕТ ПРОВЕРКИ",
        "UNKNOWN" => "НЕИЗВЕСТНО",
        "BLOCKING" => "БЛОКИРУЕТ ГЕНЕРАЦИЮ",
        "BLOCKED" => "ЗАБЛОКИРОВАНО",
        "READY" => "ГОТОВО",
        "READY_TO_GENERATE" => "ГОТОВО К ГЕНЕРАЦИИ",
        "START" => "ГОТОВО К ЗАГРУЗКЕ",
        "VERIFIED" => "ПРОВЕРЕНО",
        "PASS" => "ПРОЙДЕНО",
        "FAIL" => "ОШИБКА",
        "NOT RUN" => "НЕ ЗАПУЩЕНО",
        "INFO" => "СВЕДЕНИЯ",
        "ERROR" => "ОШИБКА",
        "VERIFICATION_FAILED" => "ПРОВЕРКА НЕ ПРОЙДЕНА"
      }.freeze

      RATIONALE_LABELS = {
        "operationId/path/method provide a deterministic operation candidate" => "operationId, путь и метод однозначно определяют назначение операции.",
        "path/method provide a structural operation candidate" => "Путь и метод дают структурное назначение операции.",
        "status text/path/response evidence identifies a status read" => "Текст статуса, путь и ответ указывают на операцию чтения статуса.",
        "webhook/callback evidence identifies a callback operation" => "Признаки webhook/callback указывают на операцию обратного вызова.",
        "unbound action is preserved as an extra operation" => "Непривязанное действие сохраняется как дополнительная операция.",
        "generic transaction identity is ambiguous without a payout-like lifecycle signal" => "Без признаков жизненного цикла выплаты назначение транзакции неоднозначно.",
        "operation identity signals conflict across operationId and path" => "Признаки назначения операции конфликтуют между operationId и путём.",
        "an explicit supported security scheme is present" => "В спецификации явно указан поддерживаемый способ авторизации.",
        "no supported explicit authentication scheme was found" => "Поддерживаемый явный способ авторизации не найден.",
        "spec description and case default disagree on provider amount unit" => "Описание спецификации и case default расходятся в единице суммы провайдера.",
        "the request schema does not expose a direct amount field" => "Схема запроса не содержит прямого поля суммы.",
        "host and provider amount units are explicit and directional conversion is deterministic" => "Единицы суммы хоста и провайдера указаны явно; пересчёт однозначен.",
        "both host and provider amount units are required before conversion" => "Для пересчёта необходимо подтвердить единицы суммы хоста и провайдера.",
        "every provider status has an explicit case-default canonical mapping" => "Для каждого статуса провайдера задано явное каноническое сопоставление.",
        "one or more provider statuses have plausible but unconfirmed terminal aliases" => "Для одного или нескольких статусов есть возможные, но неподтверждённые терминальные варианты.",
        "one or more provider statuses lack a confirmed canonical mapping" => "Для одного или нескольких статусов нет подтверждённого канонического сопоставления.",
        "no webhook endpoint; polling-only provider" => "Webhook не найден; интеграция работает только через опрос статуса.",
        "no webhook endpoint was discovered; preserve polling-only integration" => "Webhook не обнаружен; сохраняется интеграция только через опрос статуса.",
        "endpoint, signature header, algorithm, raw body, encoding and event outcomes are represented" => "Адрес webhook, заголовок подписи, алгоритм, сырое тело, кодировка и исходы событий описаны.",
        "webhook verification requires endpoint and complete signature/event semantics" => "Для проверки webhook нужны адрес и полное описание подписи и событий.",
        "header presence and requiredness are read from the OpenAPI parameter" => "Наличие заголовка и его обязательность прочитаны из параметра OpenAPI.",
        "no explicit idempotency parameter was found" => "Явный параметр идемпотентности не найден.",
        "all conditional phrases were parsed without relying on a fixed branch count" => "Все условные правила разобраны без фиксированного числа ветвей.",
        "one or more conditional phrases need review" => "Одно или несколько условных правил требуют проверки.",
        "canonical fields have explicit direct or transformed mappings" => "Для канонических полей заданы явные прямые или преобразованные сопоставления.",
        "one or more canonical field mappings are unresolved" => "Одно или несколько канонических сопоставлений полей не разрешены.",
        "structured request constraints are preserved for generated validation" => "Структурные ограничения запроса сохранены для проверки в generated adapter.",
        "create request schema is missing" => "Схема create request отсутствует.",
        "no response model was found" => "Модель ответа не найдена.",
        "known and example-only provider codes are represented with conservative retry policies" => "Известные и приведённые только в примерах коды сохранены с осторожной retry-политикой."
      }.freeze

      def upload_page
        content = <<~HTML
          <section class="hero-copy">
            <h1>Загрузите спецификацию провайдера</h1>
            <p>YAML, YML или JSON. Спецификация анализируется локально и никуда не отправляется.</p>
          </section>
          <form class="upload-form" method="post" action="/analyze" enctype="multipart/form-data">
            <label class="dropzone" for="spec-file">
              <span class="eyebrow accent">OpenAPI</span>
              <strong>Перетащите provider_api.yaml сюда</strong>
              <span>или выберите файл на диске</span>
              <span class="button button-secondary">Выбрать файл</span>
              <input id="spec-file" name="spec_file" type="file" accept=".yaml,.yml,.json,application/yaml,application/json" required>
            </label>
            <button class="button button-primary" type="submit">Анализировать спецификацию</button>
          </form>
          <section class="demo-section">
            <h2>Быстрый демо-режим</h2>
            <p>Готовые сценарии для проверки положительного пути, безопасной остановки и универсальности.</p>
            <div class="demo-grid">
              #{demo_card("novapay", "NovaPay", "Официальный кейс", "READY", "ready")}
              #{demo_card("ambiguous", "Ambiguous", "Неизвестная единица amount", "BLOCKED", "blocked")}
              #{demo_card("aurora", "Aurora", "Другая структура провайдера", "REVIEW_REQUIRED", "review")}
            </div>
          </section>
        HTML
        layout(nil, active: "spec", title: "Новая интеграция", subtitle: "OpenAPI → проверенный Ruby-адаптер провайдера", state: "START", content: content)
      end

      def analysis_page(workspace, selected_id = nil)
        blueprint = workspace.blueprint
        summary = workspace.manifest.to_h.fetch("summary")
        decisions = Array(blueprint["decisions"])
        selected = decisions.find { |item| item["decision_id"] == selected_id.to_s } || decisions.find { |item| item["decision_id"] == "money:amount-units" } || decisions.first
        endpoints = Array(blueprint["endpoints"])
        status_map = Array(blueprint["statuses"])
        auth = blueprint.dig("auth", "strategy") || {}
        auth_label = case auth.fetch("kind", "UNKNOWN").to_s
                     when "api_key" then "API-ключ · #{auth["name"]} · заголовок"
                     when "bearer" then "Bearer · #{auth["name"] || "Authorization"} · заголовок"
                     else "Способ авторизации не определён"
                     end
        money = blueprint.fetch("money")
        webhook = blueprint.fetch("webhook")
        content = <<~HTML
          <div class="page-heading split-heading">
            <div>
              <h1>Анализ спецификации</h1>
              <p>#{h(endpoints.length)} конечных точек · #{h(summary.fetch("decisions"))} решений · #{h(summary.fetch("review_required"))} требуют проверки · #{h(summary.fetch("blocking"))} блокируют генерацию</p>
            </div>
            <div class="pill-row">
              #{status_pill("#{summary.fetch("accepted")} ПРИНЯТО", "ready")}
              #{status_pill("#{summary.fetch("review_required")} ТРЕБУЕТ ПРОВЕРКИ", summary.fetch("review_required").positive? ? "review" : "muted")}
              #{status_pill("#{summary.fetch("blocking")} БЛОКИРУЕТ ГЕНЕРАЦИЮ", summary.fetch("blocking").positive? ? "blocked" : "muted")}
            </div>
          </div>
          <div class="analysis-grid">
            <section class="card operations-card">
              <div class="card-heading">
                <div><h2>Операции</h2><p>Как конечные точки провайдера сопоставлены с контрактом Space Payments</p></div>
              </div>
              <div class="operation-list">
                #{endpoints.map { |endpoint| operation_row(workspace, endpoint) }.join}
              </div>
            </section>
            <section class="card facts-card">
                <h2>Параметры интеграции</h2>
                <div class="fact-block">
                <span class="label">Авторизация</span>
                <strong>#{h(auth_label)}</strong>
                #{status_pill(decision_outcome(decisions, "auth:security-schemes"), tone_for(decision_outcome(decisions, "auth:security-schemes")))}
              </div>
              <div class="divider"></div>
              <div class="fact-block fact-with-action">
                <span class="label">Деньги</span>
                <strong>#{h(semantic_label(money.dig("host", "unit")))} #{h(money.dig("host", "currency"))} → #{h(semantic_label(money.dig("provider", "unit")))} #{h(money.dig("provider", "currency"))}</strong>
                <span>×#{h(money.dig("request_conversion", "factor"))} · #{h(unit_label(money.dig("provider", "unit_name")))}</span>
                <a href="/workspace/#{workspace.id}/analysis?decision=money%3Aamount-units">Почему?</a>
              </div>
              <div class="divider"></div>
              <div class="fact-block fact-with-action">
                <span class="label">Webhook</span>
                <strong>#{h(semantic_label(webhook.dig("signature", "algorithm")))} · #{h(semantic_label(webhook.dig("signature", "encoding")))}</strong>
                <span>#{h(webhook.dig("signature", "header"))}</span>
                <a href="/workspace/#{workspace.id}/analysis?decision=webhook%3Asignature">Почему?</a>
              </div>
            </section>
            <section class="card status-card">
              <h2>Сопоставление статусов</h2>
              #{status_map.map { |item| "<div class=\"mapping-row\"><span>#{h(item["provider_value"])}</span><span class=\"arrow\">→</span><strong>#{h(semantic_label(item["canonical_value"]))}</strong></div>" }.join}
              #{status_map.empty? ? '<p class="muted">Статусы не обнаружены.</p>' : ""}
            </section>
            <section class="card evidence-card">
              <h2>Почему принято это решение?</h2>
              #{render_decision(selected)}
            </section>
          </div>
          <section class="detail-grid">
            #{detail_section("Идемпотентность", "idempotency:header", blueprint.fetch("idempotency"), decisions, workspace)}
            #{detail_section("Сопоставление полей", "fields:create-request", blueprint.fetch("field_mappings"), decisions, workspace)}
            #{detail_section("Ограничения", "constraints:create-request", blueprint.fetch("constraints"), decisions, workspace)}
            #{detail_section("Ошибки", "errors:provider-model", blueprint.fetch("errors"), decisions, workspace)}
          </section>
        HTML
        layout(workspace, active: "analysis", title: workspace_title(workspace), subtitle: workspace_subtitle(workspace), state: display_state(workspace), content: content)
      end

      def review_page(workspace)
        decisions = workspace.unresolved_decisions
        blocking = workspace.blocking_decisions
        summary = workspace.manifest.to_h.fetch("summary")
        content = <<~HTML
          <div class="page-heading split-heading">
            <div>
              <h1>#{blocking.empty? ? "Проверка не требуется" : "Требуется подтверждение"}</h1>
              <p>#{blocking.empty? ? "Все критические решения разрешены." : "#{blocking.length} критических неоднозначностей блокируют генерацию."}</p>
            </div>
            <div class="pill-row">
              #{status_pill("#{blocking.length} БЛОКИРУЕТ ГЕНЕРАЦИЮ", blocking.empty? ? "muted" : "blocked")}
              #{status_pill("#{decisions.count { |item| item["outcome"] == "REVIEW_REQUIRED" }} ТРЕБУЕТ ПРОВЕРКИ", decisions.empty? ? "muted" : "review")}
            </div>
          </div>
          #{blocking.empty? ? "" : '<div class="blocking-alert"><strong>Генерация заблокирована</strong><span>Нерешённые критические решения нельзя безопасно превратить в сгенерированный адаптер.</span></div>'}
          #{decisions.empty? ? happy_review_card(summary, workspace) : decisions.map { |decision| review_decision_card(workspace, decision) }.join}
          #{blocking.empty? ? "" : '<div class="blocked-action"><strong>Сгенерировать интеграцию</strong><span>Сначала проверьте решения, блокирующие генерацию</span></div>'}
        HTML
        layout(workspace, active: "review", title: workspace_title(workspace), subtitle: workspace_subtitle(workspace), state: display_state(workspace), content: content)
      end

      def preview_page(workspace, kind = "request")
        unless workspace.accepted?
          content = <<~HTML
            <div class="page-heading"><h1>Предпросмотр преобразований</h1><p>Предпросмотр доступен только для разрешённого Blueprint без решений, блокирующих генерацию.</p></div>
            <section class="card empty-card"><h2>Предпросмотр заблокирован</h2><p>Текущий результат: #{h(status_label(workspace.blueprint["decision"]))}. Сначала разрешите критические неоднозначности.</p><a class="button button-secondary" href="/workspace/#{workspace.id}/review">Открыть проверку</a></section>
          HTML
          return layout(workspace, active: "preview", title: workspace_title(workspace), subtitle: workspace_subtitle(workspace), state: display_state(workspace), content: content)
        end

        result = workspace.preview_results[kind.to_s]
        content = <<~HTML
          <div class="page-heading">
            <h1>Предпросмотр преобразований</h1>
            <p>Используются те же Blueprint и runtime-семантика, что и в сгенерированном адаптере.</p>
          </div>
          <nav class="tabs" aria-label="Тип предпросмотра">
            #{preview_tab(workspace, "request", "Запрос", kind)}
            #{preview_tab(workspace, "response", "Ответ", kind)}
            #{preview_tab(workspace, "webhook", "Webhook", kind)}
          </nav>
          #{preview_content(workspace, kind, result)}
        HTML
        layout(workspace, active: "preview", title: workspace_title(workspace), subtitle: "provider_api.yaml · Blueprint v1", state: display_state(workspace), content: content)
      end

      def generate_page(workspace, artifact_name = nil)
        unless workspace.accepted?
          content = <<~HTML
            <div class="page-heading"><h1>Генерация заблокирована</h1><p>Сгенерированный адаптер нельзя выпустить, пока Blueprint содержит нерешённые критические решения.</p></div>
            <section class="card empty-card"><h2>Генерация недоступна</h2><p>Текущий результат: #{h(status_label(workspace.blueprint["decision"]))}.</p><a class="button button-secondary" href="/workspace/#{workspace.id}/review">Открыть проверку</a></section>
          HTML
          return layout(workspace, active: "generate", title: workspace_title(workspace), subtitle: workspace_subtitle(workspace), state: display_state(workspace), content: content)
        end

        verification = workspace.verification
        artifact = if workspace.generated?
                     selected = Web::ARTIFACTS.include?(artifact_name.to_s) ? artifact_name.to_s : "service.rb"
                     { "name" => selected, "content" => workspace.artifact(selected) }
                   end
        content = <<~HTML
          <div class="page-heading split-heading">
            <div>
              <h1>#{workspace.generated? ? "Интеграция сгенерирована" : "Готово к генерации"}</h1>
              <p>#{generation_subtitle(workspace, verification)}</p>
            </div>
            #{workspace.generated? ? "" : '<form method="post" action="/workspace/' + workspace.id + '/generate"><button class="button button-primary" type="submit">Сгенерировать интеграцию</button></form>'}
          </div>
          <div class="generate-grid">
            <section class="card readiness-card">
              <h2>Готовность</h2>
              #{readiness_rows(workspace)}
              <div class="divider"></div>
              <div class="readiness-counts"><span>Блокируют #{workspace.blocking_decisions.length}</span><span>Требуют проверки #{workspace.blueprint["decisions"].count { |item| item["outcome"] == "REVIEW_REQUIRED" }}</span><span>Неизвестно #{workspace.blueprint["decisions"].count { |item| item["outcome"] == "UNKNOWN" }}</span></div>
            </section>
            #{workspace.generated? ? artifact_panel(workspace, artifact) : '<section class="card empty-card"><h2>Сгенерированные файлы</h2><p>После запуска здесь появятся service.rb, Blueprint, Manifest, fixtures и результаты проверки.</p></section>'}
          </div>
          #{workspace.generated? ? verification_panel(workspace, verification) : ""}
        HTML
        layout(workspace, active: "generate", title: workspace_title(workspace), subtitle: "provider_api.yaml · детерминированный результат", state: generation_state(workspace), content: content)
      end

      def error_page(message)
        user_message = localized_error(message)
        content = <<~HTML
          <div class="page-heading"><h1>Не удалось обработать спецификацию</h1><p>Проверьте входной файл и повторите попытку.</p></div>
          <section class="card error-card"><strong>Ошибка</strong><p>#{h(user_message)}</p><details class="technical-details"><summary>Технические подробности</summary><pre>#{h(message)}</pre></details><a class="button button-secondary" href="/">Вернуться к загрузке</a></section>
        HTML
        layout(nil, active: "spec", title: "Новая интеграция", subtitle: "OpenAPI → проверенный Ruby-адаптер провайдера", state: "ERROR", content: content)
      end

      private

      def layout(workspace, active:, title:, subtitle:, state:, content:)
        <<~HTML
          <!doctype html>
          <html lang="ru">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>#{h(title)} · Provider Compiler</title>
              <link rel="stylesheet" href="/static/app.css">
            </head>
            <body>
              <aside class="sidebar">
                <div class="brand"><span>PROVIDER</span><strong>COMPILER</strong><small>Рабочая панель интеграций</small></div>
                <nav class="side-nav" aria-label="Этапы работы">
                  #{NAV_ITEMS.map { |key, label, route| nav_item(workspace, active, key, label, route) }.join}
                </nav>
                <div class="sidebar-footer">Hack.Genesis 2026<br><span>Ruby · без нейросетевого runtime</span></div>
              </aside>
              <main class="app-shell">
                <header class="topbar"><div><strong>#{h(title)}</strong><span>#{h(subtitle)}</span></div>#{status_pill(state, tone_for(state))}</header>
                <div class="content">#{content}</div>
              </main>
              <script src="/static/app.js" defer></script>
            </body>
          </html>
        HTML
      end

      def nav_item(workspace, active, key, label, route)
        if workspace
          href = key == "spec" ? "/" : "/workspace/#{workspace.id}/#{route}"
          %(<a class="nav-item #{active == key ? "active" : ""}" href="#{href}">#{h(label)}</a>)
        else
          %(<span class="nav-item #{active == key ? "active" : "disabled"}">#{h(label)}</span>)
        end
      end

      def demo_card(name, title, subtitle, state, tone)
        <<~HTML
          <form class="demo-card" method="post" action="/demo">
            <input type="hidden" name="demo" value="#{h(name)}">
            <button type="submit" aria-label="Загрузить пример #{h(title)}">
              <strong>#{h(title)}</strong><span>#{h(subtitle)}</span>#{status_pill(state, tone)}
            </button>
          </form>
        HTML
      end

      def operation_row(workspace, endpoint)
        canonical = endpoint["canonical"]
        decision_id = "operation:#{Util.slug(endpoint["operation_id"] || endpoint["method"].to_s + endpoint["path"].to_s)}"
        extra = canonical.nil?
        <<~HTML
          <div class="operation-row">
            #{method_pill(endpoint["method"])}
            <code>#{h(endpoint["path"])}</code>
            <span class="operation-id">#{h(endpoint["operation_id"] || "(без operationId)")}</span>
            <strong class="binding #{extra ? "muted" : ""}">→ #{h(extra ? "Дополнительная операция · EXTRA_OPERATION" : canonical)}</strong>
            <a href="/workspace/#{workspace.id}/analysis?decision=#{url_escape(decision_id)}">Почему?</a>
          </div>
        HTML
      end

      def render_decision(decision)
        return '<p class="muted">Решения отсутствуют.</p>' unless decision

        evidence = Array(decision["evidence"])
        <<~HTML
          <span class="label">#{h(decision["decision_id"])}</span>
          <p class="decision-summary">#{h(rationale_summary(decision["rationale"]))}</p>
          #{evidence.map { |item| evidence_row(item) }.join}
          #{Array(decision["conflicts"]).empty? ? "" : "<div class=\"conflicts\"><span class=\"label\">Конфликты</span>#{json_block(decision["conflicts"])}</div>"}
          <div class="decision-result">Решение: #{h(status_label(decision["outcome"]))} · #{h(severity_label(decision["severity"]))}</div>
          <details class="technical-details"><summary>Технические подробности</summary><p>rationale: #{h(decision["rationale"])}</p></details>
        HTML
      end

      def evidence_row(item)
        <<~HTML
          <div class="evidence-row"><div class="evidence-source"><span class="label">Источник</span>#{status_pill(item["source"], "source")}</div><div class="evidence-value"><span class="label">Факт</span><span>#{h(item["excerpt"] || "")}</span><span class="label">Расположение</span><code>#{h(Array(item["locations"]).join(", "))}</code></div></div>
        HTML
      end

      def review_decision_card(workspace, decision)
        candidate = decision["candidate"]
        title = decision_title(decision["decision_id"])
        <<~HTML
          <section class="card review-card">
            <div class="review-card-heading"><div><h2>#{h(title)}</h2><span class="label">решение: #{h(decision["decision_id"])}</span></div>#{status_pill(decision["outcome"], tone_for(decision["outcome"]))}</div>
            <div class="review-summary-grid"><div><span class="label">Известно</span><p>#{h(review_known(decision["decision_id"]))}</p></div><div><span class="label">Не хватает данных</span><p>#{h(review_unknown(decision["decision_id"]))}</p></div><div><span class="label">Почему генерация заблокирована?</span><p>#{h(rationale_summary(decision["rationale"]))}</p></div></div>
            <div class="review-columns"><div><span class="label">Предлагаемый вариант</span>#{json_block(candidate)}</div><div><span class="label">Основания</span>#{Array(decision["evidence"]).map { |item| evidence_row(item) }.join}<span class="label">Обоснование</span><p>#{h(rationale_summary(decision["rationale"]))}</p><details class="technical-details"><summary>Технические подробности</summary><p>rationale: #{h(decision["rationale"])}</p></details></div></div>
            <div class="review-actions"><button class="button button-primary" disabled title="Сохранение решений в рабочей области недоступно">Подтвердить вариант</button><button class="button button-secondary" disabled title="Сохранение решений в рабочей области недоступно">Изменить решение</button><span>Слой сохранения решений не подключён; решение остаётся в безопасном режиме.</span></div>
          </section>
        HTML
      end

      def detail_section(title, decision_id, value, decisions, workspace)
        decision = decisions.find { |item| item["decision_id"] == decision_id }
        <<~HTML
          <details class="card detail-card"><summary><strong>#{h(title)}</strong>#{status_pill(decision ? decision["outcome"] : "INFO", decision ? tone_for(decision["outcome"]) : "muted")}</summary><div class="detail-body">#{json_block(value)}#{decision ? "<a href=\"/workspace/#{workspace.id}/analysis?decision=#{url_escape(decision_id)}\">Почему принято это решение?</a>" : ""}</div></details>
        HTML
      end

      def preview_content(workspace, kind, result)
        case kind.to_s
        when "request" then request_preview(workspace, result)
        when "response" then response_preview(workspace, result)
        when "webhook" then webhook_preview(workspace, result)
        else request_preview(workspace, result)
        end
      end

      def request_preview(workspace, result)
        operation = result && result["host_input"] || { "amount" => "1500.50", "currency" => "RUB", "external_id" => "demo-001", "recipient" => { "type" => "sbp", "phone" => "79001234567", "bank_code" => "044525225" } }
        request = result && result["provider_request"]
        money = workspace.blueprint.fetch("money")
        conversion = result && result["conversion"] || money.fetch("request_conversion")
        provider_path = money.dig("provider", "field").to_s.sub("request.", "")
        provider_amount = request && dig_path(request["body"], provider_path)
        result_value = if result
                         %(<strong class="provider-value">#{h(provider_amount)}</strong><span>#{h(unit_label(money.dig("provider", "unit_name")))}</span>)
                       else
                         %(<strong class="pending-value">Ожидает запуска</strong><span>Результат появится после запуска</span>)
                       end
        <<~HTML
          <div class="preview-grid">
            <section class="card host-input-card"><h2>ВХОДНЫЕ ДАННЫЕ SPACE PAYMENTS</h2><p>Операция Space Payments</p><form method="post" action="/workspace/#{workspace.id}/preview"><input type="hidden" name="kind" value="request">#{input_field("amount", operation["amount"])}#{input_field("currency", operation["currency"])}#{input_field("external_id", operation["external_id"])}#{input_field("recipient_type", operation.dig("recipient", "type"))}#{input_field("recipient_phone", operation.dig("recipient", "phone"))}#{input_field("recipient_bank_code", operation.dig("recipient", "bank_code"))}<button class="button button-primary" type="submit">Запустить предпросмотр</button></form></section>
            <section class="card transformation-card"><h2>ПРЕОБРАЗОВАНИЕ</h2><p>Разрешённый Blueprint</p><span class="label">operation.amount</span><strong class="big-value">#{h(operation["amount"])} #{h(operation["currency"])}</strong><span class="down-arrow">↓</span><span class="conversion-pill">#{h(conversion_label(conversion))}</span><strong class="factor">#{h(conversion_factor_label(conversion))}</strong><span class="down-arrow">↓</span>#{result_value}<div class="divider"></div><span class="label">Доказательное преобразование</span><small>источник: Blueprint.money</small></section>
            <section class="card provider-request-card"><h2>ЗАПРОС ПРОВАЙДЕРУ</h2><div class="request-line">#{method_pill(workspace.blueprint.dig("endpoints", 0, "method"))}<code>#{h(workspace.blueprint.dig("endpoints", 0, "path"))}</code></div>#{request ? json_block(request) : '<p class="empty-hint">Нажмите «Запустить предпросмотр», чтобы построить реальный запрос через сгенерированный адаптер.</p>'}<small>Авторизация: #{h(workspace.blueprint.dig("auth", "strategy", "name"))} · Idempotency-Key, если доступен</small></section>
          </div>
        HTML
      end

      def response_preview(workspace, result)
        provider_body = result && result["provider_response"] && result["provider_response"]["body"]
        provider_status = provider_body && provider_body["status"]
        host_status = result && result.dig("host_result", "status")
        response_amount = result && result.dig("host_result", "amount")
        conversion = workspace.blueprint.fetch("money").fetch("response_conversion")
        projection = if result
                       %(<span class="label">#{h(provider_status)}</span><span class="down-arrow">↓</span><span class="conversion-pill">#{h(conversion_label(conversion))} #{h(conversion_factor_label(conversion))}</span><strong class="provider-value">#{h(format_amount(response_amount))}</strong><span>#{h(workspace.blueprint.dig("money", "host", "currency"))}</span><div class="divider"></div><strong>#{h(provider_status)} → #{h(host_status)}</strong>)
                     else
                       %(<strong class="pending-value">Ожидает запуска</strong><span>Ответ и преобразование появятся после запуска</span>)
                     end
        <<~HTML
          <div class="preview-grid response-grid"><section class="card code-card"><h2>ОТВЕТ ПРОВАЙДЕРА</h2><p>Фикстура ответа для демо</p>#{result ? json_block(result["provider_response"]) : '<p class="empty-hint">Нажмите «Запустить предпросмотр», чтобы получить ответ провайдера.</p>'}#{result ? "" : preview_button(workspace, "response")}</section><section class="card transformation-card"><h2>АКТУАЛЬНАЯ ПРОЕКЦИЯ</h2><p>Сопоставление сгенерированного адаптера</p>#{projection}</section><section class="card code-card"><h2>РЕЗУЛЬТАТ SPACE PAYMENTS</h2><p>Канонический результат</p>#{result ? json_block(result["host_result"]) : '<p class="empty-hint">Результат появится после запуска предпросмотра.</p>'}</section></div>
        HTML
      end

      def webhook_preview(workspace, result)
        event = result && result["event"]
        callback = result && result["result"]
        callback_status = callback && callback["status"]
        callback_action = callback && callback["action"]
        mapping = if result
                    %(<strong>#{h(event)}</strong><span class="down-arrow">↓</span><span class="conversion-pill">#{h(callback_status)}</span><strong class="provider-value">#{h(callback_action)}</strong><span>терминальное событие: да</span>)
                  else
                    %(<strong class="pending-value">Ожидает запуска</strong><span>Событие и действие появятся после запуска</span>)
                  end
        <<~HTML
          <div class="preview-grid webhook-grid"><section class="card code-card"><h2>ВХОДЯЩИЙ WEBHOOK</h2><p>Демо-payload; секрет не показывается</p>#{result ? json_block("event" => result["event"], "signature_model" => result["signature_model"]) : '<p class="empty-hint">Нажмите «Запустить предпросмотр», чтобы проверить webhook.</p>'}#{result ? "" : preview_button(workspace, "webhook")}</section><section class="card transformation-card"><h2>СОПОСТАВЛЕНИЕ CALLBACK</h2><p>Поведение сгенерированного адаптера</p>#{mapping}</section><section class="card code-card"><h2>ДЕЙСТВИЕ SPACE PAYMENTS</h2><p>Канонический результат callback</p>#{result ? json_block(result["result"]) : '<p class="empty-hint">Результат появится после запуска предпросмотра.</p>'}</section></div>
        HTML
      end

      def artifact_panel(workspace, artifact)
        tabs = Web::ARTIFACTS.map do |name|
          active = artifact && artifact["name"] == name ? "active" : ""
          %(<a class="artifact-tab #{active}" href="/workspace/#{workspace.id}/generate?artifact=#{url_escape(name)}">#{h(name)}</a>)
        end.join
        <<~HTML
          <section class="card artifacts-card"><div class="card-heading"><div><h2>Сгенерированные файлы</h2><p>Детерминированный результат разрешённого Blueprint</p></div></div><div class="artifact-tabs">#{tabs}</div><div class="artifact-toolbar"><a class="button button-secondary" href="/workspace/#{workspace.id}/artifact?name=#{url_escape(artifact["name"])}&download=1">Скачать файл</a><a class="button button-secondary" href="/workspace/#{workspace.id}/bundle">Скачать всё</a><button class="button button-secondary copy-button" data-copy-target="artifact-viewer" type="button">Копировать</button></div><pre id="artifact-viewer" class="artifact-viewer">#{h(artifact["content"])}</pre></section>
        HTML
      end

      def preview_button(workspace, kind)
        %(<form class="preview-run-form" method="post" action="/workspace/#{workspace.id}/preview"><input type="hidden" name="kind" value="#{h(kind)}"><button class="button button-primary" type="submit">Запустить предпросмотр</button></form>)
      end

      def verification_panel(workspace, verification)
        checks = [
          ["Проверка Blueprint", true],
          ["Обязательные файлы", Web::ARTIFACTS.all? { |name| File.file?(File.join(workspace.generated_dir, name)) }],
          ["Синтаксис Ruby", verification.fetch("syntax").all? { |item| item["passed"] }],
          ["Контрактная проверка", verification.dig("smoke", "passed")]
        ]
        preview_checks = [["Проекция запроса", workspace.preview_results.key?("request") ? true : nil], ["Проекция ответа", workspace.preview_results.key?("response") ? true : nil], ["Сопоставление статусов", workspace.preview_results.key?("response") ? true : nil], ["Обработка webhook", workspace.preview_results.key?("webhook") ? true : nil]]
        all_checks = checks + preview_checks
        <<~HTML
          <section class="card verification-card"><h2>Проверка результата</h2><div class="verification-grid">#{all_checks.map { |name, passed| verification_row(name, passed) }.join}</div><details class="technical-details"><summary>Технический результат</summary>#{json_block(verification)}</details></section>
        HTML
      end

      def readiness_rows(workspace)
        decisions = Array(workspace.blueprint["decisions"])
        generated = workspace.generated?
        rows = [
          ["Разбор спецификации", true, :readiness],
          ["Операции", decision_prefix_accept?(decisions, "operation:"), :readiness],
          ["Авторизация", decision_outcome(decisions, "auth:security-schemes") == "ACCEPT", :readiness],
          ["Деньги", workspace.blueprint.dig("money", "decision") == "ACCEPT", :readiness],
          ["Статусы", status_ready?(workspace.blueprint), :readiness],
          ["Webhook", workspace.blueprint.dig("webhook", "decision") == "ACCEPT", :readiness],
          ["Сопоставление полей", Array(workspace.blueprint["field_mappings"]).all? { |item| item["decision"] == "ACCEPT" }, :readiness],
          ["Сгенерированный Ruby", generated ? workspace.verification.dig("syntax", 0, "passed") : nil, :verification],
          ["Runtime smoke", generated ? workspace.verification.dig("smoke", "passed") : nil, :verification]
        ]
        rows.map { |name, ready, kind| readiness_row(name, ready, kind) }.join
      end

      def readiness_row(name, passed, kind = :readiness)
        value = if passed.nil?
                  "NOT RUN"
                elsif passed
                  kind == :verification ? "PASS" : "READY"
                else
                  kind == :verification ? "FAIL" : "REVIEW_REQUIRED"
                end
        tone = passed.nil? ? "muted" : tone_for(value)
        %(<div class="readiness-row"><span class="status-dot #{passed == true ? "ready" : (passed == false ? "blocked" : "pending")}"></span><span>#{h(name)}</span>#{status_pill(value, tone)}</div>)
      end

      def happy_review_card(summary, workspace)
        <<~HTML
          <section class="card empty-card review-success-card">
            <h2>Проверка не требуется</h2>
            <p>Все критические решения разрешены.</p>
            <div class="review-counts"><span>#{h(summary.fetch("accepted"))} решений принято</span><span>#{h(summary.fetch("review_required"))} требуют проверки</span><span>#{h(summary.fetch("blocking"))} блокирующих</span></div>
            <div class="review-actions"><a class="button button-primary" href="/workspace/#{workspace.id}/preview">Перейти к предпросмотру</a><a class="button button-secondary" href="/workspace/#{workspace.id}/generate">Перейти к генерации</a></div>
          </section>
        HTML
      end

      def decision_title(decision_id)
        labels = {
          "amount-units" => "Единицы суммы",
          "security-schemes" => "Способ авторизации",
          "provider-map" => "Сопоставление статусов",
          "signature" => "Подпись webhook",
          "header" => "Идемпотентность",
          "conditional-required" => "Условные ограничения",
          "create-request" => "Сопоставление полей",
          "provider-model" => "Модель ошибок провайдера"
        }
        key = decision_id.to_s.split(":", 2).last
        labels.fetch(key, key.to_s.tr("-", " ").capitalize)
      end

      def review_unknown(decision_id)
        case decision_id.to_s
        when "money:amount-units" then "Единица суммы провайдера и коэффициент пересчёта."
        when "fields:create-request" then "Однозначная связь полей запроса с контрактом Space Payments."
        when "status:provider-map" then "Подтверждённое каноническое значение статуса."
        when "webhook:signature" then "Полные правила проверки подписи webhook."
        else "Данные для безопасного решения по #{decision_id}."
        end
      end

      def review_known(decision_id)
        case decision_id.to_s
        when "money:amount-units" then "Поле operation.amount и единица суммы хоста доступны из профиля."
        when "fields:create-request" then "Поля запроса и ответа провайдера доступны в OpenAPI."
        when "status:provider-map" then "Значения статусов провайдера прочитаны из OpenAPI."
        when "webhook:signature" then "Адрес webhook и доступные параметры подписи показаны в основаниях."
        else "Доступные факты OpenAPI и профиля показаны в основаниях."
        end
      end

      def rationale_summary(rationale)
        RATIONALE_LABELS.fetch(rationale.to_s, "Техническое обоснование доступно в технических подробностях.")
      end

      def status_label(value)
        STATUS_LABELS.fetch(value.to_s, value.to_s)
      end

      def severity_label(value)
        { "BLOCKING" => "БЛОКИРУЕТ ГЕНЕРАЦИЮ", "WARNING" => "ПРЕДУПРЕЖДЕНИЕ", "INFO" => "СВЕДЕНИЯ" }.fetch(value.to_s, value.to_s)
      end

      def unit_label(value)
        { "UNKNOWN" => "НЕИЗВЕСТНО", "kopecks" => "копеек", "minor" => "минимальных единиц", "major" => "основных единиц" }.fetch(value.to_s, value.to_s)
      end

      def semantic_label(value)
        value.to_s == "UNKNOWN" ? "НЕИЗВЕСТНО" : value.to_s
      end

      def conversion_label(conversion)
        case conversion["direction"].to_s
        when "major_to_minor" then "major → minor"
        when "minor_to_major" then "minor → major"
        when "same_unit" then "без пересчёта"
        else conversion["direction"].to_s.tr("_", " ")
        end
      end

      def conversion_factor_label(conversion)
        if conversion["operation"].to_s == "divide"
          "/#{conversion["scale"] || conversion["factor"]}"
        else
          "× #{conversion["factor_decimal"] || conversion["factor"]}"
        end
      end

      def format_amount(value)
        return "—" if value.nil?

        text = BigDecimal(value.to_s).to_s("F")
        integer, fraction = text.split(".", 2)
        "#{integer}.#{fraction.to_s.ljust(2, "0")[0, 2]}"
      rescue ArgumentError
        value.to_s
      end

      def generation_subtitle(workspace, verification)
        return "Blueprint разрешён для детерминированной генерации." unless workspace.generated?

        if verification && verification["passed"]
          "Ruby-сервис, документация и fixtures успешно созданы и прошли обязательные проверки."
        else
          "Артефакты созданы, но одна или несколько обязательных проверок не пройдены."
        end
      end

      def generation_state(workspace)
        return "VERIFIED" if workspace.generated? && workspace.verification && workspace.verification["passed"]
        return "VERIFICATION_FAILED" if workspace.generated? && workspace.verification

        "READY_TO_GENERATE"
      end

      def verification_row(name, passed)
        value = passed.nil? ? "NOT RUN" : (passed ? "PASS" : "FAIL")
        tone = passed.nil? ? "muted" : (passed ? "ready" : "blocked")
        %(<div class="verification-row"><span class="status-dot #{passed == true ? "ready" : (passed == false ? "blocked" : "pending")}"></span><span>#{h(name)}</span>#{status_pill(value, tone)}</div>)
      end

      def input_field(name, value)
        label = name.to_s.tr("_", ".")
        %(<label class="input-label">#{h(label)}<input name="#{h(name)}" value="#{h(value)}"></label>)
      end

      def preview_tab(workspace, kind, label, active_kind)
        %(<a class="tab #{kind == active_kind ? "active" : ""}" href="/workspace/#{workspace.id}/preview?kind=#{kind}">#{h(label)}</a>)
      end

      def json_block(value)
        %(<pre class="code-block">#{h(JSON.pretty_generate(normalize(value)))}</pre>)
      rescue StandardError
        %(<pre class="code-block">#{h(value.inspect)}</pre>)
      end

      def normalize(value)
        case value
        when Hash then value.each_with_object({}) { |(key, item), result| result[key.to_s] = normalize(item) }
        when Array then value.map { |item| normalize(item) }
        when BigDecimal then value.to_s("F")
        else value
        end
      end

      def dig_path(value, path)
        path.to_s.split(".").reduce(value) { |current, key| current.is_a?(Hash) ? (current[key] || current[key.to_sym]) : nil }
      end

      def status_ready?(blueprint)
        values = Array(blueprint["statuses"])
        !values.empty? && values.all? { |item| item["decision"] == "ACCEPT" }
      end

      def decision_prefix_accept?(decisions, prefix)
        relevant = decisions.select { |item| item["decision_id"].to_s.start_with?(prefix) }
        !relevant.empty? && relevant.all? { |item| item["outcome"] == "ACCEPT" }
      end

      def decision_outcome(decisions, id)
        decisions.find { |item| item["decision_id"] == id }&.fetch("outcome", "UNKNOWN") || "UNKNOWN"
      end

      def workspace_title(workspace)
        workspace.blueprint.dig("provider", "name") || "Провайдер"
      end

      def workspace_subtitle(workspace)
        "#{workspace.filename} · fp #{fingerprint_short(workspace)}"
      end

      def fingerprint_short(workspace)
        fingerprint = workspace.blueprint.dig("source", "spec_fingerprint").to_s.split(":", 2).last
        fingerprint.to_s[0, 10] + (fingerprint.to_s.length > 10 ? "…" : "")
      end

      def display_state(workspace)
        return "START" unless workspace.analyzed?
        return "BLOCKED" if workspace.blocking_decisions.any?
        return "UNKNOWN" if workspace.blueprint["decision"] == "UNKNOWN"
        return "REVIEW REQUIRED" if workspace.blueprint["decision"] == "REVIEW_REQUIRED"

        "READY"
      end

      def method_pill(method)
        tone = method.to_s.upcase == "GET" ? "method-get" : "method-post"
        %(<span class="method-pill #{tone}">#{h(method)}</span>)
      end

      def status_pill(label, tone)
        %(<span class="status-pill #{h(tone)}">#{h(status_label(label))}</span>)
      end

      def tone_for(value)
        text = value.to_s
        return "ready" if %w[ACCEPT READY VERIFIED PASS READY_TO_GENERATE].include?(text)
        return "blocked" if %w[BLOCKED UNKNOWN FAIL ERROR VERIFICATION_FAILED].include?(text)
        return "review" if text.include?("REVIEW") || text == "START"
        "muted"
      end

      def localized_error(message)
        text = message.to_s
        return "Поддерживаются только файлы YAML, YML и JSON." if text.include?("only YAML, YML and JSON")
        return "Выберите файл OpenAPI в формате YAML, YML или JSON." if text.include?("choose an OpenAPI")
        return "Не удалось прочитать загрузку файла. Проверьте формат multipart." if text.include?("invalid multipart")
        return "Не удалось прочитать OpenAPI-файл. Проверьте синтаксис YAML/JSON." if text.include?("cannot parse OpenAPI input")
        return "Не удалось прочитать OpenAPI-файл с диска." if text.include?("cannot read OpenAPI input")
        return "Удалённые $ref не поддерживаются. Используйте локальные ссылки внутри загруженного набора файлов." if text.include?("remote $ref is not allowed")
        return "Ссылка $ref выходит за пределы загруженного набора файлов." if text.include?("$ref escapes allowed root")
        return "Не удалось разрешить локальную ссылку $ref в OpenAPI-файле." if text.include?("unresolved $ref") || text.include?("cannot read $ref document")
        return "Спецификация прочитана, но обязательные данные для построения интеграции не найдены." if text.include?("openapi must be") || text.include?("paths must be") || text.include?("info.title is required") || text.include?("info.version is required")
        return "Генерация недоступна: есть критические решения, требующие проверки." if text.include?("generation is blocked")
        return "Предпросмотр недоступен для текущего Blueprint." if text.include?("preview is unavailable")
        return "Неизвестный тип предпросмотра." if text.include?("unsupported preview")
        return "Рабочая область не найдена." if text.include?("workspace not found")
        return "Неизвестный файл артефакта." if text.include?("unknown artifact")
        return "Сначала выполните генерацию артефактов." if text.include?("artifacts have not been generated")
        return "Файл спецификации слишком большой. Максимальный размер — #{Regexp.last_match(1)} байт." if text =~ /uploaded specification is too large \(limit: (\d+) bytes\)/

        "Не удалось выполнить операцию. Проверьте входные данные."
      end

      def h(value)
        ERB::Util.html_escape(value.to_s)
      end

      def url_escape(value)
        WEBrick::HTTPUtils.escape_form(value.to_s)
      end
    end
  end
end
