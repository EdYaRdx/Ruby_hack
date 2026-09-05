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
        "structured request constraints are preserved for generated validation" => "Структурные ограничения запроса сохранены для проверки в сгенерированном адаптере.",
        "create request schema is missing" => "Схема create request отсутствует.",
        "no response model was found" => "Модель ответа не найдена.",
        "known and example-only provider codes are represented with conservative retry policies" => "Известные и приведённые только в примерах коды сохранены с осторожной retry-политикой."
      }.freeze

      def upload_page
        content = <<~HTML
          <section class="landing-hero">
            <div class="hero-copy">
              <span class="eyebrow accent">PROVIDER COMPILER · DEMO WORKBENCH</span>
              <h1>Из OpenAPI — в проверенную интеграцию</h1>
              <p>Система отделяет факты спецификации от бизнес-семантики, которую нельзя безопасно угадать.</p>
            </div>
            <div class="story-strip" aria-label="Путь интеграции">
              <span>OpenAPI</span><b>→</b><span>Доказанные факты</span><b>→</b><span>Review</span><b>→</b><span>Provider Blueprint</span><b>→</b><span>Ruby adapter</span>
            </div>
          </section>

          <section class="mode-section">
            <div class="section-heading"><div><h2>Выберите режим работы</h2><p>Один и тот же провайдер может получить разный результат — в зависимости от явно переданных правил.</p></div></div>
            <div class="mode-grid">
              <article class="mode-panel mode-panel-upload">
                <div class="mode-panel-heading"><span class="mode-icon">↥</span><div><h3>Новый анализ OpenAPI</h3><span class="mode-kicker">Только OpenAPI</span></div></div>
                <p>Загрузите OpenAPI провайдера. Используются только спецификация и контракт Space Payments.</p>
                <p class="mode-note">Если критическая бизнес-семантика не доказана документом, она попадёт на Review.</p>
                <form class="upload-form" method="post" action="/analyze" enctype="multipart/form-data">
                  <label class="dropzone" for="spec-file">
                    <span class="eyebrow accent">OpenAPI YAML / JSON</span>
                    <strong>Выберите спецификацию</strong>
                    <span>или перетащите файл сюда · обработка локально</span>
                    <span class="button button-secondary">Выбрать OpenAPI</span>
                    <input id="spec-file" name="spec_file" type="file" accept=".yaml,.yml,.json,application/yaml,application/json" required>
                  </label>
                  <button class="button button-primary" type="submit">Анализировать спецификацию</button>
                </form>
                <small>Дополнительные правила провайдера не подмешиваются автоматически.</small>
              </article>
              <article class="mode-panel mode-panel-explainer">
                <span class="eyebrow">ПОЧЕМУ ЭТО ВАЖНО</span>
                <h3>Review — безопасная остановка перед генерацией</h3>
                <p>OpenAPI хорошо описывает HTTP API, но не всегда содержит смысл финансовых полей, статусов и webhook.</p>
                <div class="mode-comparison"><div><strong>Только OpenAPI</strong><span>Только доказуемые факты</span><em>Нерешённые вопросы → Review</em></div><div><strong>Сценарий с подтверждёнными правилами</strong><span>OpenAPI + подтверждённые правила</span><em>Критические решения разрешены</em></div></div>
                <details class="inline-details"><summary>Что произойдёт после проверки?</summary><p>После подтверждения нерешённых вопросов Blueprint пересоберётся, предпросмотр покажет реальные преобразования, а генерация создаст детерминированный Ruby adapter и проверки.</p></details>
              </article>
            </div>
          </section>

          <section class="demo-section">
            <div class="section-heading"><div><h2>Демо-сценарии</h2><p>Явно разделены режимы «только OpenAPI» и «с подтверждёнными правилами».</p></div></div>
            <div class="demo-grid demo-grid-primary">
              #{demo_card("novapay_spec_only", "NovaPay — только OpenAPI", "Честный анализ только по официальной спецификации", "ТРЕБУЕТ ПРОВЕРКИ", "review", "Запустить анализ по OpenAPI")}
              #{demo_card("novapay", "NovaPay — с подтверждёнными правилами", "OpenAPI + заранее подтверждённые правила провайдера", "ГОТОВО К ГЕНЕРАЦИИ", "ready", "Открыть подтверждённый пример")}
            </div>
          </section>
          <section class="demo-section secondary-demos">
            <div class="section-heading"><div><h2>Другие провайдеры</h2><p>Проверка универсальности на другой структуре API.</p></div></div>
            <div class="demo-grid demo-grid-secondary">
              #{demo_card("aurora", "Aurora", "Другая структура provider API", "ТРЕБУЕТ ПРОВЕРКИ", "review", "Открыть анализ")}
              #{demo_card("heliospay", "HeliosPay — с подтверждёнными правилами", "Независимый провайдер с другой структурой API", "ГОТОВО К ГЕНЕРАЦИИ", "ready", "Открыть подтверждённый пример")}
              #{demo_card("ambiguous", "Неоднозначный provider", "Безопасная остановка на неизвестной сумме", "ТРЕБУЕТ ПРОВЕРКИ", "review", "Открыть Review")}
            </div>
          </section>
        HTML
        layout(nil, active: "spec", title: "Новая интеграция", subtitle: "OpenAPI → проверенный Ruby-адаптер провайдера", state: "START", content: content)
      end

      def analysis_page(workspace, selected_id = nil)
        blueprint = workspace.blueprint
        summary = workspace.manifest.to_h.fetch("summary")
        decisions = Array(blueprint["decisions"])
        endpoints = Array(blueprint["endpoints"])
        status_map = Array(blueprint["statuses"])
        money = blueprint.fetch("money")
        webhook = blueprint.fetch("webhook")
        canonical_endpoints = endpoints.reject { |endpoint| endpoint["canonical"].nil? }
        extra_endpoints = endpoints.select { |endpoint| endpoint["canonical"].nil? }
        unresolved = workspace.unresolved_decisions
        total = summary.fetch("decisions")
        headline_status = unresolved.empty? ? "READY" : "REVIEW REQUIRED"
        status_decision = find_decision(decisions, "status:provider-map")
        status_copy = if status_decision && status_decision["outcome"] == "ACCEPT"
                        "#{status_map.length} статусов сопоставлены со Space Payments."
                      else
                        "Найдено #{status_map.length} статусов провайдера. Их соответствие Space Payments требует подтверждения."
                      end
        mode = workspace.case_pack ? "Сценарий с подтверждёнными правилами" : "Только OpenAPI"
        mode_note = workspace.case_pack ? "Использованы OpenAPI и явно подтверждённые правила провайдера." : "Использовалась только спецификация OpenAPI."
        content = <<~HTML
          <section class="analysis-hero">
            <div class="analysis-hero-copy">
              <span class="eyebrow accent">#{h(mode)}</span>
              <h1>#{h(workspace_title(workspace))}</h1>
              <h2>Анализ OpenAPI завершён</h2>
              <p class="analysis-lead"><strong>#{h(summary.fetch("accepted"))} из #{h(total)} решений</strong> определены автоматически.</p>
              <p class="analysis-lead #{unresolved.empty? ? "success-copy" : "review-copy"}">#{unresolved.empty? ? "Все критические решения разрешены — можно открыть предпросмотр." : "#{h(summary.fetch("review_required"))} решения нужно подтвердить перед генерацией."}</p>
              <div class="analysis-hero-actions">
                <a class="button button-#{unresolved.empty? ? "primary" : "secondary"}" href="/workspace/#{workspace.id}/#{unresolved.empty? ? "preview" : "review"}">#{unresolved.empty? ? "Перейти к предпросмотру" : "Проверить #{summary.fetch("review_required")} решения"}</a>
                <details class="inline-details"><summary>Почему нужна проверка?</summary><p>OpenAPI описывает структуру API, но может не содержать смысл финансовых полей, статусов или webhook.</p></details>
              </div>
            </div>
            <div class="analysis-hero-status">#{status_pill(status_label(headline_status), tone_for(headline_status))}<span>#{h(mode_note)}</span></div>
          </section>
          <section class="semantic-section">
            <div class="section-heading"><div><h2>Что система определила</h2><p>Краткое резюме решений; технические основания доступны внутри деталей.</p></div></div>
            <div class="semantic-grid">#{semantic_area_rows(blueprint, decisions)}</div>
          </section>
          <div class="analysis-grid">
            <section class="card operations-card">
              <div class="card-heading">
                <div><h2>Операции</h2><p>#{h(canonical_endpoints.length)} канонических · #{h(extra_endpoints.length)} дополнительных</p></div>
              </div>
              <div class="operation-list">
                #{endpoints.map { |endpoint| operation_row(workspace, endpoint, decisions) }.join}
              </div>
            </section>
            <section class="card facts-card">
                <h2>Ключевые решения</h2>
                <div class="fact-block">
                <span class="label">Авторизация</span>
                <strong>#{h(auth_summary(blueprint))}</strong>
              </div>
              <div class="divider"></div>
              <div class="fact-block fact-with-action">
                <span class="label">Деньги</span>
                <strong>#{h(money_summary(money))}</strong>
                <span>#{h(money_detail(money))}</span>
                #{explainability_block(decision: find_decision(decisions, "money:amount-units"), result: money_summary(money), explanation: money_explanation(money), technical_data: { "money" => money })}
              </div>
              <div class="divider"></div>
              <div class="fact-block fact-with-action">
                <span class="label">Webhook</span>
                <strong>#{h(webhook_summary(webhook))}</strong>
                <span>#{h(webhook.dig("signature", "header") || "Endpoint не определён")}</span>
                #{explainability_block(decision: find_decision(decisions, "webhook:signature"), result: webhook_summary(webhook), explanation: webhook_explanation(webhook), technical_data: { "webhook" => webhook })}
              </div>
            </section>
            <section class="card status-card">
              <h2>Статусы операций</h2>
              <p class="card-intro">#{h(status_copy)}</p>
              #{status_mapping_rows(status_map.first(2))}
              #{status_map.length > 2 ? "<details class=\"inline-details\"><summary>Показать все</summary>#{status_mapping_rows(status_map.drop(2))}</details>" : ""}
              #{explainability_block(decision: status_decision, result: status_decision && status_decision["outcome"] == "ACCEPT" ? "#{status_map.length} сопоставлений подтверждено" : "Сопоставление требует подтверждения", explanation: status_copy, technical_data: { "statuses" => status_map }, compact: true)}
              #{status_map.empty? ? '<p class="muted">Статусы не обнаружены.</p>' : ""}
            </section>
            <section class="card focus-card">
              <h2>#{unresolved.empty? ? "Готово к предпросмотру" : "Следующий шаг"}</h2>
              <p>#{unresolved.empty? ? "Blueprint разрешён. Посмотрите реальные запрос, ответ и преобразование webhook." : "#{unresolved.length} решений требуют подтверждения перед безопасной генерацией."}</p>
              <a class="button button-#{unresolved.empty? ? "primary" : "secondary"}" href="/workspace/#{workspace.id}/#{unresolved.empty? ? "preview" : "review"}">#{unresolved.empty? ? "Перейти к предпросмотру" : "Открыть проверку"}</a>
            </section>
          </div>
          <section class="detail-grid">
            #{detail_section("Идемпотентность", "idempotency:header", blueprint.fetch("idempotency"), decisions, workspace)}
            #{detail_section("Сопоставление полей", "fields:create-request", blueprint.fetch("field_mappings"), decisions, workspace)}
            #{detail_section("Ограничения", "constraints:create-request", blueprint.fetch("constraints"), decisions, workspace)}
            #{detail_section("Обработка ошибок API", "errors:provider-model", blueprint.fetch("errors"), decisions, workspace)}
          </section>
        HTML
        layout(workspace, active: "analysis", title: workspace_title(workspace), subtitle: workspace_subtitle(workspace), state: display_state(workspace), content: content)
      end

      def review_page(workspace)
        decisions = workspace.unresolved_decisions
        summary = workspace.manifest.to_h.fetch("summary")
        needs_review = !decisions.empty?
        active_decision = decisions.first
        content = <<~HTML
          <section class="review-hero">
            <div>
              <span class="eyebrow accent">БЕЗОПАСНАЯ ПРОВЕРКА</span>
              <h1>#{needs_review ? "Требуется подтвердить #{decisions.length} решения" : "Проверка не требуется"}</h1>
              <p>#{needs_review ? "OpenAPI не содержит достаточно информации для безопасной генерации. Мы не угадываем критический смысл финансовых полей и статусов." : "Все критические решения разрешены — можно перейти к предпросмотру и генерации."}</p>
            </div>
            <div class="review-hero-status">#{status_pill(needs_review ? "REVIEW REQUIRED" : "READY", needs_review ? "review" : "ready")}<strong>#{needs_review ? "Нерешённые вопросы" : "Blueprint разрешён"}</strong></div>
          </section>
          #{needs_review ? "<div class=\"review-progress\"><div><strong>#{decisions.length} решения требуют подтверждения</strong><span>Шаг 1 из #{decisions.length}</span></div><div class=\"progress-track\"><span style=\"width: #{(100.0 / decisions.length).round(1)}%\"></span></div><small>После подтверждения автоматически откроется следующий нерешённый вопрос.</small></div>" : ""}
          #{decisions.empty? ? happy_review_card(summary, workspace) : review_decision_card(workspace, active_decision, 1, decisions.length)}
          #{needs_review && decisions.length > 1 ? review_queue(decisions.drop(1), 2) : ""}
        HTML
        layout(workspace, active: "review", title: workspace_title(workspace), subtitle: workspace_subtitle(workspace), state: display_state(workspace), content: content)
      end

      def preview_page(workspace, kind = "request")
        unless workspace.accepted?
          unresolved = workspace.unresolved_decisions
          unresolved_list = unresolved.map { |decision| unresolved_list_item(decision) }.join
          content = <<~HTML
            <div class="page-heading"><span class="eyebrow accent">ПРЕДПРОСМОТР</span><h1>Предпросмотр преобразований</h1><p>Здесь будут показаны реальные запрос, ответ и преобразование webhook из Blueprint.</p></div>
            <section class="blocked-workflow">
              <div><span class="blocked-icon" aria-hidden="true">!</span><div><h2>Предпросмотр станет доступен после проверки</h2><p>#{unresolved.length} решения ещё не подтверждены. Это ожидаемая защитная остановка, а не ошибка приложения.</p></div></div>
              <ul class="unresolved-list">#{unresolved_list}</ul>
              <a class="button button-primary" href="/workspace/#{workspace.id}/review">Проверить #{unresolved.length} решения</a>
            </section>
          HTML
          return layout(workspace, active: "preview", title: workspace_title(workspace), subtitle: workspace_subtitle(workspace), state: display_state(workspace), content: content)
        end

        result = workspace.preview_results[kind.to_s]
        content = <<~HTML
          <div class="page-heading">
            <h1>Предпросмотр преобразований</h1>
            <p>Используются те же Provider Blueprint и runtime-правила, что и в сгенерированном адаптере.</p>
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
          unresolved = workspace.unresolved_decisions
          unresolved_list = unresolved.map { |decision| unresolved_list_item(decision) }.join
          content = <<~HTML
            <div class="page-heading"><span class="eyebrow accent">ГЕНЕРАЦИЯ</span><h1>Генерация недоступна</h1><p>Сначала подтвердите критические решения — после этого появятся Ruby adapter, документация и fixtures.</p></div>
            <section class="blocked-workflow">
              <div><span class="blocked-icon" aria-hidden="true">!</span><div><h2>Осталось подтвердить #{unresolved.length} решений</h2><p>Режим проверки — ожидаемый этап, а не ошибка приложения.</p></div></div>
              <ul class="unresolved-list">#{unresolved_list}</ul>
              <a class="button button-primary" href="/workspace/#{workspace.id}/review">Перейти к проверке</a>
            </section>
          HTML
          return layout(workspace, active: "generate", title: workspace_title(workspace), subtitle: workspace_subtitle(workspace), state: display_state(workspace), content: content)
        end

        verification = workspace.verification
        artifact = if workspace.generated?
                     selected = Web::ARTIFACTS.include?(artifact_name.to_s) ? artifact_name.to_s : "service.rb"
                     { "name" => selected, "content" => workspace.artifact(selected) }
                   end
        content = <<~HTML
          <div class="page-heading split-heading generation-hero">
            <div>
              <span class="eyebrow accent">ГЕНЕРАЦИЯ</span>
              <h1>#{workspace.generated? ? "✓ Интеграция сгенерирована" : "Готово к генерации"}</h1>
              <p>#{generation_subtitle(workspace, verification)}</p>
              <div class="generation-summary"><strong>#{workspace.generated? ? Web::ARTIFACTS.length : Web::ARTIFACTS.length} файлов #{workspace.generated? ? "создано" : "будет создано"}</strong><span class="generation-check-note">#{workspace.generated? ? (verification && verification["passed"] ? "Обязательные проверки пройдены" : "Обязательная проверка не пройдена") : "#{workspace.blueprint["decisions"].length} из #{workspace.blueprint["decisions"].length} решений разрешены"}</span></div>
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
        step_state = navigation_state(workspace, active, key)
        indicator = { "done" => "✓", "current" => "→", "needs_action" => "!", "locked" => "🔒", "available" => "○" }.fetch(step_state)
        state_label = { "done" => "готово", "current" => "текущий шаг", "needs_action" => "нужно действие", "locked" => "заблокировано", "available" => "доступно" }.fetch(step_state)
        content = %(<span class="nav-indicator" aria-hidden="true">#{indicator}</span><span class="nav-label">#{h(label)}</span><span class="nav-state">#{h(state_label)}</span>)
        if workspace
          href = key == "spec" ? "/" : "/workspace/#{workspace.id}/#{route}"
          %(<a class="nav-item #{active == key ? "active" : ""} state-#{step_state}" href="#{href}" aria-current="#{active == key ? "step" : "false"}">#{content}</a>)
        else
          %(<span class="nav-item #{active == key ? "active" : "disabled"} state-#{step_state}">#{content}</span>)
        end
      end

      def navigation_state(workspace, active, key)
        return active == key ? "current" : "locked" unless workspace
        return "done" if key == "spec" && workspace.analyzed? && active != "spec"
        return "current" if active == key

        unresolved = !workspace.unresolved_decisions.empty?
        case key
        when "spec" then "done"
        when "analysis" then "done"
        when "review" then unresolved ? "needs_action" : "done"
        when "preview" then workspace.accepted? ? "available" : "locked"
        when "generate" then workspace.generated? ? "done" : (workspace.accepted? ? "available" : "locked")
        else "locked"
        end
      end

      def demo_card(name, title, subtitle, state, tone, action = "Открыть сценарий")
        <<~HTML
          <form class="demo-card" method="post" action="/demo">
            <input type="hidden" name="demo" value="#{h(name)}">
            <button type="submit" aria-label="Загрузить пример #{h(title)}">
              <span class="demo-card-topline"><span class="demo-arrow" aria-hidden="true">→</span><span>#{h(action)}</span></span>
              <strong>#{h(title)}</strong><span>#{h(subtitle)}</span>#{status_pill(state, tone)}
            </button>
          </form>
        HTML
      end

      def money_summary(money)
        return "Требует проверки: единицы суммы" unless money["decision"] == "ACCEPT"

        provider_unit = money.dig("provider", "unit") == "minor" ? "копейки" : "основные единицы"
        "✓ #{money.dig("host", "currency")} → #{provider_unit} · #{conversion_factor_label(money.fetch("request_conversion"))}"
      end

      def money_detail(money)
        return "Нужно подтвердить major/minor и scale" unless money["decision"] == "ACCEPT"

        "operation.amount: #{money.dig("host", "unit")} · provider: #{money.dig("provider", "unit_name")}"
      end

      def webhook_summary(webhook)
        return "Требует проверки: правила подписи" unless webhook["decision"] == "ACCEPT"

        "✓ #{webhook.dig("signature", "algorithm")} · #{webhook.dig("signature", "encoding")}"
      end

      def status_mapping_rows(items)
        items.map do |item|
          canonical = item["canonical_value"]
          candidate = item["candidate_canonical_value"]
          value = canonical == "UNKNOWN" ? "не подтверждено" : semantic_label(canonical)
          suggestion = canonical == "UNKNOWN" && candidate ? "<small>Предложение: #{h(candidate)}</small>" : ""
          "<div class=\"mapping-row\"><span>#{h(item["provider_value"])}</span><span class=\"arrow\">→</span><strong>#{h(value)}#{suggestion}</strong></div>"
        end.join
      end

      def auth_summary(blueprint)
        auth = blueprint.dig("auth", "strategy") || {}
        case auth.fetch("kind", "UNKNOWN").to_s
        when "api_key" then "API-ключ · #{auth["name"]} · заголовок"
        when "bearer" then "Bearer · #{auth["name"] || "Authorization"} · заголовок"
        else "Способ авторизации требует проверки"
        end
      end

      def semantic_area_rows(blueprint, decisions)
        areas = [
          ["Операции", decision_prefix_accept?(decisions, "operation:"), "HTTP-пути → create_request / fetch_status"],
          ["Авторизация", decision_outcome(decisions, "auth:security-schemes") == "ACCEPT", auth_summary(blueprint)],
          ["Деньги", blueprint.dig("money", "decision") == "ACCEPT", money_summary(blueprint.fetch("money"))],
          ["Статусы", status_ready?(blueprint), Array(blueprint["statuses"]).length.positive? ? "Сопоставление со Space Payments" : "Статусы не найдены"],
          ["Webhook", blueprint.dig("webhook", "decision") == "ACCEPT", webhook_summary(blueprint.fetch("webhook"))],
          ["Сопоставление полей", Array(blueprint["field_mappings"]).all? { |item| item["decision"] == "ACCEPT" }, "Канонические поля запроса и ответа"],
          ["Идемпотентность", decision_outcome(decisions, "idempotency:header") == "ACCEPT", "Заголовок и правила повторов"],
          ["Ошибки", decision_outcome(decisions, "errors:provider-model") == "ACCEPT", "Правила ошибок HTTP и провайдера"]
        ]
        areas.map do |label, ready, summary|
          state = ready ? "Определено" : "Требует подтверждения"
          icon = ready ? "✓" : "!"
          %(<div class="semantic-item #{ready ? "is-ready" : "is-review"}"><span class="semantic-icon" aria-hidden="true">#{icon}</span><div><strong>#{h(label)}</strong><span>#{h(summary)}</span></div><span class="semantic-state">#{h(state)}</span></div>)
        end.join
      end

      def operation_row(workspace, endpoint, decisions)
        canonical = endpoint["canonical"]
        decision_id = "operation:#{Util.slug(endpoint["operation_id"] || endpoint["method"].to_s + endpoint["path"].to_s)}"
        decision = find_decision(decisions, decision_id)
        extra = canonical.nil?
        binding = if extra
                    '<strong class="binding muted">Дополнительная операция <span class="technical-label">EXTRA_OPERATION</span></strong>'
                  else
                    "<strong class=\"binding\">→ #{h(canonical)}</strong>"
                  end
        <<~HTML
          <div class="operation-row">
            #{method_pill(endpoint["method"])}
            <code>#{h(endpoint["path"])}</code>
            <span class="operation-id">#{h(endpoint["operation_id"] || "(без operationId)")}</span>
            #{binding}
            <details class="operation-details">
              <summary>Подробнее</summary>
              <div class="operation-detail-body">
                <span class="label">Определено как</span>
                <strong>#{h(extra ? "Дополнительная операция" : canonical)}</strong>
                <p>#{h(operation_explanation(endpoint, canonical))}</p>
                #{explainability_block(decision: decision, result: extra ? "EXTRA_OPERATION" : canonical, explanation: operation_explanation(endpoint, canonical), technical_data: { "endpoint" => endpoint })}
              </div>
            </details>
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

      def review_decision_card(workspace, decision, position = 1, total = 1)
        candidate = decision["candidate"]
        title = decision_title(decision["decision_id"])
        <<~HTML
          <section class="card review-card review-card-active">
            <div class="review-card-heading"><div><span class="step-label">РЕШЕНИЕ #{position} ИЗ #{total}</span><h2>#{h(review_question(decision["decision_id"]))}</h2></div><div class="pill-row">#{status_pill(decision["outcome"], "review")}#{decision["severity"] == "BLOCKING" ? status_pill(severity_label(decision["severity"]), "blocked") : ""}</div></div>
            <div class="review-columns">
              <div class="review-state review-known"><span class="label">1 · ИЗВЕСТНО</span><p>#{h(review_known(decision["decision_id"]))}</p><details class="inline-details"><summary>Показать evidence</summary>#{evidence_rows_compact(decision)}</details></div>
              <div class="review-state review-proposal"><span class="label">2 · ПРЕДЛОЖЕНИЕ СИСТЕМЫ</span><p>#{human_candidate_summary(decision, workspace)}</p><small>Предложение не считается выбранным значением.</small></div>
            </div>
            <div class="review-impact"><span class="label">ПОЧЕМУ ЭТО ВАЖНО</span><p>#{h(review_impact(decision["decision_id"]))}</p></div>
            <div class="review-choice"><span class="label">3 · ВАШ ВЫБОР</span><p>Подтвердите только значение, которое следует из документации провайдера.</p>#{resolution_form(workspace, decision)}</div>
            #{explainability_block(decision: decision, action_label: "Основания предложения", result: "Предложение требует подтверждения", explanation: review_proposal_explanation(decision), technical_data: { "candidate" => candidate })}
          </section>
        HTML
      end

      def evidence_rows_compact(decision)
        evidence = Array(decision["evidence"])
        return '<p class="muted">Evidence не найден.</p>' if evidence.empty?

        evidence.map { |item| human_evidence_row(item) }.join
      end

      def review_queue(decisions, start_position)
        items = decisions.each_with_index.map do |decision, index|
          %(<li><span class="queue-number">#{start_position + index}</span><div><strong>#{h(review_question(decision["decision_id"]))}</strong><span>#{h(decision["severity"] == "BLOCKING" ? "Критическое решение" : "Требует подтверждения")}</span></div><span class="queue-state">#{h(decision_title(decision["decision_id"]))}</span></li>)
        end.join
        %(<section class="review-queue"><h2>Следующие решения</h2><p>Остальные вопросы откроются по одному после подтверждения текущего.</p><ol>#{items}</ol></section>)
      end

      def unresolved_list_item(decision)
        %(<li><span class="status-icon review">!</span><span>#{h(review_question(decision["decision_id"]))}</span></li>)
      end

      def review_question(decision_id)
        {
          "money:amount-units" => "В каких единицах провайдер принимает сумму?",
          "status:provider-map" => "Как статусы провайдера переводятся в Space Payments?",
          "fields:create-request" => "Какие данные передавать в запрос провайдера?",
          "webhook:signature" => "Как проверять webhook провайдера?",
          "idempotency:header" => "Как обрабатывать повторы запроса?"
        }.fetch(decision_id, decision_title(decision_id))
      end

      def human_candidate_summary(decision, workspace = nil)
        case decision["decision_id"]
        when "money:amount-units"
          candidate_unit = decision.dig("candidate", "provider_unit")
          candidate_scale = decision.dig("candidate", "request_conversion", "scale")
          "Space Payments: major RUB → единица провайдера: #{candidate_unit == "UNKNOWN" ? "не определена" : candidate_unit || "не определена"}; масштаб: #{candidate_scale || "не определён"}. Подтвердите оба значения."
        when "status:provider-map"
          status_mapping_rows(Array(decision["candidate"]))
        when "fields:create-request"
          Array(decision["candidate"]).select { |item| item["decision"] != "ACCEPT" || item["transform"].to_s == "unresolved" }.map { |item| "<div class=\"mapping-row review-mapping\"><span>#{h(item["canonical_path"])}</span><span class=\"arrow\">→</span><strong>#{h(item["provider_path"] || "?")}</strong></div>" }.join
        when "webhook:signature"
          candidate = decision["candidate"] || {}
          webhook = workspace&.blueprint&.fetch("webhook", {}) || {}
          "Endpoint: #{webhook["endpoint"] || "не определён"} · заголовок: #{webhook.dig("signature", "header") || "не определён"} · #{candidate["algorithm"] || "алгоритм не подтверждён"} · кодировка: #{candidate["encoding"] || "не определена"}."
        when "idempotency:header"
          "OpenAPI не показывает обязательный заголовок. Подтвердите его отсутствие или укажите имя заголовка."
        else
          h(rationale_summary(decision["rationale"]))
        end
      end

      def resolution_form(workspace, decision)
        id = decision["decision_id"]
        form_content = case id
                       when "money:amount-units"
                         candidate = decision["candidate"] || {}
                         conversion = candidate["request_conversion"] || {}
                         candidate_unit = %w[minor major].include?(candidate["provider_unit"].to_s) ? candidate["provider_unit"].to_s : nil
                         unit = nil
                         scale = nil
                          <<~HTML
                           <label class="input-label">Единица провайдера<select name="provider_unit" required><option value="">Выберите значение</option><option value="minor"#{unit == "minor" ? " selected" : ""}>minor — минимальные единицы</option><option value="major"#{unit == "major" ? " selected" : ""}>major — основные единицы</option></select></label>
                            <small class="proposal-note">Предложение системы: #{candidate_unit ? "единица провайдера: #{candidate_unit}" : "единица не определена"} · это не подтверждённый выбор.</small>
                           <label class="input-label">Подразделение<input name="provider_subunit" value="" placeholder="Например, kopecks" required></label>
                            <label class="input-label">Масштаб пересчёта (scale)<input name="scale" value="#{h(scale)}" placeholder="Укажите масштаб" inputmode="numeric" required></label>
                           <small class="form-helper">Для RUB обычно 100 копеек = 1 рубль, но подтвердите значение по документации провайдера.</small>
                         HTML
                       when "status:provider-map"
                         Array(decision["candidate"]).each_with_index.map { |item, index| status_resolution_input(item, index) }.join
                       when "fields:create-request"
                         Array(decision["candidate"]).each_with_index.filter_map do |item, index|
                           next if item["decision"] == "ACCEPT" && item["transform"].to_s != "unresolved"

                           field_resolution_input(item, index)
                         end.join
                       when "webhook:signature"
                         candidate_encoding = %w[base64 hex].include?(decision.dig("candidate", "encoding").to_s) ? decision.dig("candidate", "encoding").to_s : nil
                         webhook_resolution_input(candidate_encoding)
                        when "idempotency:header"
                          idempotency_resolution_input(decision.dig("candidate", "header"))
                       else
                          '<p class="muted">Для этого решения нужен отдельный ввод по провайдеру. Генерация остаётся недоступной.</p>'
                       end
        action = form_content.include?("отдельный ввод по провайдеру") ? "" : %(<form class="resolution-form" method="post" action="/workspace/#{workspace.id}/review"><input type="hidden" name="decision_id" value="#{h(id)}">#{form_content}<button class="button button-primary" type="submit">#{h(resolution_action_label(id))}</button></form>)
        action
      end

      def resolution_action_label(decision_id)
        {
          "status:provider-map" => "Подтвердить соответствия",
          "fields:create-request" => "Подтвердить сопоставления",
          "webhook:signature" => "Подтвердить webhook",
          "idempotency:header" => "Подтвердить решение",
          "money:amount-units" => "Подтвердить решение"
        }.fetch(decision_id.to_s, "Подтвердить решение")
      end

      def status_resolution_input(item, index)
        selected = item["canonical_value"] == "UNKNOWN" ? nil : item["canonical_value"]
        options = %w[in_progress approved rejected].map do |value|
          selected_attr = value == selected ? " selected" : ""
          "<option value=\"#{value}\"#{selected_attr}>#{value}</option>"
        end.join
        proposal = item["candidate_canonical_value"]
        <<~HTML
          <input type="hidden" name="status_#{index}_provider" value="#{h(item["provider_value"])}">
          <div class="status-review-row"><div><strong>#{h(item["provider_value"])}</strong><small>#{proposal ? "Предложение системы: #{h(proposal)}" : "Предложение отсутствует"}</small></div><label class="input-label resolution-select">Ваш выбор<select name="status_#{index}_value" required><option value="">Выберите значение</option>#{options}</select></label></div>
        HTML
      end

      def field_resolution_input(item, index)
        direction = item["direction"] || "request"
        amount_mapping = item["canonical_path"].to_s.end_with?("amount")
        unresolved = item["transform"] == "unresolved"
        transform = unresolved ? nil : (item["transform"] || "identity")
        factor = unresolved ? nil : (item["factor"] || 1)
        required = item["required"] ? "true" : "false"
        provider_path = item["provider_path"] == "request.amount" ? "request.amount" : item["provider_path"]
        transform_input = if amount_mapping
                            options = [["identity", "Без пересчёта"], ["money_to_provider", "major → minor"], ["provider_to_money", "minor → major"]].map do |value, label|
                              %(<option value="#{value}"#{transform == value ? " selected" : ""}>#{label}</option>)
                            end.join
                            %(<label class="input-label">Преобразование<select name="field_#{index}_transform" required><option value="">Выберите преобразование</option>#{options}</select></label><label class="input-label">Коэффициент пересчёта (factor)<input name="field_#{index}_factor" value="#{h(factor)}" placeholder="Например, 100" inputmode="decimal" required></label><small class="proposal-note">#{unresolved ? "Предложение системы: преобразование зависит от подтверждённой единицы суммы." : "Значение определено из OpenAPI."}</small>)
                          else
                            %(<input type="hidden" name="field_#{index}_transform" value="identity"><input type="hidden" name="field_#{index}_factor" value="1">)
                          end
        <<~HTML
          <input type="hidden" name="field_#{index}_canonical" value="#{h(item["canonical_path"])}">
          <input type="hidden" name="field_#{index}_direction" value="#{h(direction)}">
          <input type="hidden" name="field_#{index}_required" value="#{required}">
          <label class="input-label">#{h(item["canonical_path"])}<input name="field_#{index}_path" value="#{h(provider_path)}"></label>
          #{transform_input}
        HTML
      end

      def webhook_resolution_input(encoding)
        <<~HTML
          <input type="hidden" name="webhook_raw_body" value="true">
          <small class="proposal-note">Предложение системы: #{encoding || "кодировка не определена"} · это не подтверждённый выбор.</small>
          <label class="input-label">Ваш выбор · кодировка (encoding)<select name="webhook_encoding" required><option value="">Выберите кодировку</option><option value="hex">hex</option><option value="base64">base64</option></select></label>
        HTML
      end

      def idempotency_resolution_input(header)
        <<~HTML
          <small class="proposal-note">Предложение системы: #{header ? "найден заголовок #{h(header)}" : "обязательный заголовок не найден"} · это не подтверждённый выбор.</small>
          <label class="input-label">Ваш выбор<select name="idempotency_mode" required><option value="">Выберите вариант</option><option value="none">Заголовок отсутствует</option><option value="header">Используется заголовок</option></select></label>
          <label class="input-label">Имя заголовка<input name="idempotency_header" value="" placeholder="Например, Idempotency-Key"></label>
        HTML
      end

      def detail_section(title, decision_id, value, decisions, workspace)
        decision = decisions.find { |item| item["decision_id"] == decision_id }
        <<~HTML
          <section class="card detail-card"><div class="card-heading"><div><h2>#{h(title)}</h2><p>#{h(detail_summary(decision_id, value, decision))}</p></div>#{status_pill(decision ? decision["outcome"] : "INFO", decision ? tone_for(decision["outcome"]) : "muted")}</div>#{explainability_block(decision: decision, result: detail_summary(decision_id, value, decision), explanation: detail_explanation(decision_id, value, decision), technical_data: { "value" => value })}</section>
        HTML
      end

      def detail_summary(decision_id, value, decision)
        return "Данные отсутствуют." if value.nil? || (value.respond_to?(:empty?) && value.empty?)
        return "#{decision["outcome"] == "ACCEPT" ? "Правила распознаны." : "Нужно подтвердить часть правил."}" if decision

        case decision_id
        when "idempotency:header" then value["header"] ? "#{value["header"]}; обязательность: #{value["spec_required"]}" : "Параметр идемпотентности не найден."
        when "fields:create-request" then "#{Array(value).length} сопоставлений полей сохранено."
        when "constraints:create-request" then "#{Array(value).length} ограничений запроса сохранено."
        when "errors:provider-model" then "Сохранено правил ошибок HTTP и провайдера: #{Array(value).length}."
        else "Детали решения доступны в технических подробностях."
        end
      end

      def explainability_block(decision:, result:, explanation:, evidence: nil, conflicts: nil, technical_data: nil, action_label: "Основания решения", compact: false)
        decision ||= {}
        evidence = Array(evidence || decision["evidence"])
        conflicts = Array(conflicts || decision["conflicts"])
        technical_data ||= { "candidate" => decision["candidate"], "rationale" => decision["rationale"], "evidence" => evidence, "conflicts" => conflicts }
        source_ids = evidence.map { |item| item["source"].to_s }.reject(&:empty?).uniq
        pointers = evidence.flat_map { |item| Array(item["locations"]) }.map(&:to_s).reject(&:empty?).uniq
        source_labels = source_ids.map { |source| %(<span class="explainability-source"><span>#{h(evidence_source_label(source))}</span><code>#{h(source)}</code></span>) }.join
        evidence_html = if evidence.empty?
                          '<p class="muted">Данные для этого решения отсутствуют.</p>'
                        else
                          evidence.map { |item| human_evidence_row(item) }.join
                        end
        <<~HTML
          <details class="explainability#{compact ? " compact" : ""}">
            <summary class="explainability-trigger"><span class="explainability-icon" aria-hidden="true">ⓘ</span><span>#{h(action_label)}</span></summary>
            <div class="explainability-panel">
              <div class="explainability-result"><span class="label">Итог</span><strong>#{h(result)}</strong></div>
              <p class="explainability-human">#{h(explanation)}</p>
              <div class="explainability-evidence"><span class="label">Данные, использованные системой</span>#{evidence_html}</div>
              <div class="explainability-sources"><span class="label">Источники решения</span><div class="explainability-source-list">#{source_labels.empty? ? '<span class="muted">Не определены</span>' : source_labels}</div></div>
              <div class="explainability-conflicts"><span class="label">Конфликты</span><span>#{conflicts.empty? ? "нет" : "обнаружены: #{conflicts.length}"}</span></div>
              <details class="technical-details"><summary>Технические подробности</summary><div class="technical-meta"><span>Decision ID</span><code>#{h(decision["decision_id"] || "—")}</code><span>Provenance</span><code>#{h(source_ids.empty? ? "—" : source_ids.join(", "))}</code><span>OpenAPI pointer</span><code>#{h(pointers.empty? ? "—" : pointers.join(", "))}</code></div>#{json_block(technical_data)}</details>
            </div>
          </details>
        HTML
      end

      def human_evidence_row(item)
        source = item["source"].to_s
        <<~HTML
          <div class="human-evidence-row"><div><strong>#{h(evidence_source_label(source))}</strong><code>#{h(source)}</code></div><p>#{h(item["excerpt"] || "Данные OpenAPI или профиля")}</p></div>
        HTML
      end

      def evidence_source_label(source)
        {
          "BASE_SERVICE_PROFILE" => "Профиль Space Payments",
          "SPEC_FACT" => "Факт OpenAPI",
          "SPEC_DESCRIPTION" => "Описание OpenAPI",
          "CASE_DEFAULT" => "Профиль кейса",
          "HUMAN_CONFIRMED" => "Подтверждено человеком",
          "ADAPTER_POLICY" => "Политика адаптера",
          "UNKNOWN" => "Источник не определён"
        }.fetch(source.to_s, source.to_s)
      end

      def find_decision(decisions, decision_id)
        Array(decisions).find { |item| item["decision_id"] == decision_id }
      end

      def operation_explanation(endpoint, canonical)
        return "Endpoint сохранён без автоматической привязки к BaseService." if canonical.nil?

        "HTTP method, path и operationId дают evidence для привязки endpoint к #{canonical}."
      end

      def money_explanation(money)
        "Space Payments хранит operation.amount в #{money.dig("host", "unit")} #{money.dig("host", "currency")}; provider принимает #{money.dig("provider", "unit")} amount, поэтому применяется #{conversion_factor_label(money.fetch("request_conversion"))}."
      end

      def webhook_explanation(webhook)
        "Webhook проверяется по заявленным endpoint, алгоритму, заголовку и encoding; эти правила используются для безопасной обработки callback."
      end

      def detail_explanation(decision_id, value, decision)
        return rationale_summary(decision["rationale"]) if decision && decision["rationale"]

        case decision_id
        when "idempotency:header" then "Факт OpenAPI и отдельная политика адаптера показывают, как обрабатывать повторные запросы."
        when "fields:create-request" then "Эти соответствия определяют, какие поля проходят между Space Payments и API провайдера."
        when "constraints:create-request" then "Ограничения сохраняются для проверки сгенерированного запроса."
        when "errors:provider-model" then "Правила ошибок HTTP и провайдера определяют безопасную обработку ошибок."
        else "Техническое объяснение доступно в деталях решения."
        end
      end

      def review_impact(decision_id)
        {
          "money:amount-units" => "Ошибка преобразования изменит сумму выплаты.",
          "status:provider-map" => "Неверное сопоставление может преждевременно подтвердить или отклонить операцию.",
          "fields:create-request" => "Неверное поле или преобразование отправит провайдеру неправильные данные.",
          "webhook:signature" => "Неверная проверка подписи может принять поддельный callback.",
          "idempotency:header" => "Неверные правила повторов могут создать повторную выплату."
        }.fetch(decision_id.to_s, "Неподтверждённое решение может сделать сгенерированный адаптер небезопасным.")
      end

      def review_proposal_explanation(decision)
          "Предложение собрано из доступных фактов OpenAPI, профиля Space Payments и материалов кейса; подтвердите только значения, которые соответствуют документации провайдера."
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
        operation = result && result["host_input"]
        unless operation
          operation = ProviderCompiler::Util.deep_dup(workspace.preview_fixtures.dig("create_request", "operation") || {})
          operation["amount"] ||= "100.00"
          operation["currency"] ||= workspace.blueprint.dig("money", "host", "currency") || "XXX"
          operation["external_id"] ||= "preview-operation"
          operation["recipient"] ||= { "type" => "recipient" }
        end
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
          <div class="preview-grid preview-request-flow">
            <section class="card host-input-card"><span class="eyebrow accent">SPACE PAYMENTS</span><h2>Создание выплаты</h2><p>Входные данные канонического контракта</p><form method="post" action="/workspace/#{workspace.id}/preview"><input type="hidden" name="kind" value="request">#{input_field("amount", operation["amount"])}#{input_field("currency", operation["currency"])}#{input_field("external_id", operation["external_id"])}#{input_field("recipient_type", operation.dig("recipient", "type"))}#{input_field("recipient_phone", operation.dig("recipient", "phone"))}#{input_field("recipient_bank_code", operation.dig("recipient", "bank_code"))}<button class="button button-primary" type="submit">Запустить предпросмотр</button></form></section>
             <section class="card transformation-card"><span class="eyebrow accent">ПРЕОБРАЗОВАНИЕ</span><h2>Что изменится</h2><p>Разрешённый Provider Blueprint</p><span class="label">operation.amount</span><strong class="big-value">#{h(operation["amount"])} #{h(operation["currency"])}</strong><span class="down-arrow">↓</span><span class="conversion-pill">#{h(conversion_label(conversion))}</span><strong class="factor">#{h(conversion_factor_label(conversion))}</strong><span class="down-arrow">↓</span>#{result_value}<div class="divider"></div><span class="label">Основание преобразования</span><small>Источник: Blueprint.money и сопоставление полей</small></section>
             <section class="card provider-request-card"><span class="eyebrow accent">PROVIDER API</span><h2>Запрос провайдеру</h2><div class="request-line">#{method_pill(workspace.blueprint.dig("endpoints", 0, "method"))}<code>#{h(workspace.blueprint.dig("endpoints", 0, "path"))}</code></div>#{request ? json_block(request) : '<p class="empty-hint">Нажмите «Запустить предпросмотр», чтобы построить реальный запрос через сгенерированный адаптер.</p>'}<small>Авторизация: #{h(workspace.blueprint.dig("auth", "strategy", "name"))} · Idempotency-Key — если он доступен</small></section>
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
                    %(<strong>#{h(event)}</strong><span class="down-arrow">↓</span><span class="conversion-pill">HMAC-SHA256: подпись проверена</span><span class="down-arrow">↓</span><span class="conversion-pill">#{h(callback_status)}</span><strong class="provider-value">#{h(callback_action || "нет")}</strong><span>терминальное событие: #{callback && callback["terminal"] ? "да" : "нет"}</span>)
                  else
                    %(<strong class="pending-value">Ожидает запуска</strong><span>Событие и действие появятся после запуска</span>)
                  end
        <<~HTML
          <div class="preview-grid webhook-grid"><section class="card code-card"><span class="eyebrow accent">СОБЫТИЕ ПРОВАЙДЕРА</span><h2>Входящий webhook</h2><p>Данные события и модель подписи; секрет не показывается</p>#{result ? json_block("event" => result["event"], "signature_model" => result["signature_model"]) : '<p class="empty-hint">Нажмите «Запустить предпросмотр», чтобы проверить webhook.</p>'}#{result ? "" : preview_button(workspace, "webhook")}</section><section class="card transformation-card"><span class="eyebrow accent">ПРОВЕРКА АДАПТЕРА</span><h2>Проверка и сопоставление</h2><p>Поведение сгенерированного адаптера</p>#{mapping}</section><section class="card code-card"><span class="eyebrow accent">SPACE PAYMENTS</span><h2>Действие системы</h2><p>Канонический результат callback</p>#{result ? json_block(result["result"]) : '<p class="empty-hint">Результат появится после запуска предпросмотра.</p>'}</section></div>
        HTML
      end

      def artifact_panel(workspace, artifact)
        primary = %w[service.rb INTEGRATION.md fixtures.json]
        advanced = %w[provider_blueprint.json review_manifest.json contract_smoke.rb]
        tab_group = lambda do |names|
          names.map do |name|
          active = artifact && artifact["name"] == name ? "active" : ""
          %(<a class="artifact-tab #{active}" href="/workspace/#{workspace.id}/generate?artifact=#{url_escape(name)}">#{h(name)}</a>)
          end.join
        end
        <<~HTML
          <section class="card artifacts-card"><div class="card-heading"><div><h2>Сгенерированные файлы</h2><p>Детерминированный результат разрешённого Blueprint</p></div></div><span class="artifact-group-label">Основное</span><div class="artifact-tabs artifact-tabs-primary">#{tab_group.call(primary)}</div><span class="artifact-group-label">Дополнительно</span><div class="artifact-tabs artifact-tabs-secondary">#{tab_group.call(advanced)}</div><div class="artifact-toolbar"><a class="button button-secondary" href="/workspace/#{workspace.id}/artifact?name=#{url_escape(artifact["name"])}&download=1">Скачать файл</a><a class="button button-secondary" href="/workspace/#{workspace.id}/bundle">Скачать всё</a><button class="button button-secondary copy-button" data-copy-target="artifact-viewer" type="button">Копировать</button></div><pre id="artifact-viewer" class="artifact-viewer">#{h(artifact["content"])}</pre></section>
        HTML
      end

      def preview_button(workspace, kind)
        %(<form class="preview-run-form" method="post" action="/workspace/#{workspace.id}/preview"><input type="hidden" name="kind" value="#{h(kind)}"><button class="button button-primary" type="submit">Запустить предпросмотр</button></form>)
      end

      def verification_panel(workspace, verification)
        checks = [
          ["Синтаксис Ruby", verification.fetch("syntax").all? { |item| item["passed"] }],
          ["Контрактная проверка", verification.dig("smoke", "passed")]
        ]
        preview_checks = [["Проекция запроса", workspace.preview_results.key?("request") ? true : nil], ["Проекция ответа и статусов", workspace.preview_results.key?("response") ? true : nil], ["Поведение webhook", workspace.preview_results.key?("webhook") ? true : nil]]
        <<~HTML
          <section class="card verification-card">
            <h2>Проверка сгенерированной интеграции</h2>
            <p class="card-intro">Здесь показаны обязательные проверки генерации. Незапущенный сценарий предпросмотра не является ошибкой.</p>
            <div class="verification-section verification-required">
              <h3>Обязательные проверки</h3>
              <div class="verification-grid">#{checks.map { |name, passed| verification_row(name, passed) }.join}</div>
              <div class="verification-result #{verification["passed"] ? "passed" : "failed"}">#{verification["passed"] ? "✓ Интеграция проверена" : "Проверка интеграции не пройдена"}</div>
            </div>
            <div class="verification-section verification-optional">
              <h3>Проверенные сценарии предпросмотра</h3>
              <p>Эти сценарии запускаются вручную на экране «Предпросмотр» и не влияют на обязательную проверку генерации.</p>
              <div class="verification-grid">#{preview_checks.map { |name, passed| verification_row(name, passed) }.join}</div>
            </div>
            <details class="technical-details"><summary>Технический результат</summary>#{json_block(verification)}</details>
          </section>
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
          ["Сгенерированный Ruby-адаптер", generated ? workspace.verification.dig("syntax", 0, "passed") : nil, :verification],
          ["Проверка runtime", generated ? workspace.verification.dig("smoke", "passed") : nil, :verification]
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
            <div class="review-actions"><a class="button button-primary" href="/workspace/#{workspace.id}/preview">Перейти к предпросмотру</a><a class="button button-secondary" href="/workspace/#{workspace.id}/analysis">Посмотреть принятые решения</a></div>
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
          "Ruby-сервис, документация и fixtures успешно созданы; обязательные проверки пройдены."
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
        return "UNKNOWN" if workspace.blueprint["decision"] == "UNKNOWN"
        return "REVIEW REQUIRED" unless workspace.unresolved_decisions.empty?

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
