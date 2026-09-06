# Demo за 4 минуты

Эта инструкция предназначена для evaluator или teammate. Она запускается из
корня репозитория, использует локальные fixtures и не требует credentials.
Внешний provider sandbox не вызывается. На шаге Generate generated adapter
проверяется через реальный localhost HTTP socket.

## Подготовка

```powershell
bundle install
bundle exec rspec
bundle exec ruby bin/provider_compiler_web
```

Откройте в браузере `http://127.0.0.1:4567`. Это адрес локального Demo
Workbench, а не публичный сервис.

## 1. Home — показать pipeline

На стартовом экране покажите последовательность:

```text
OpenAPI → Facts → Analysis/Evidence → Review → Blueprint → Generate → Verification
```

В блоке сравнения видны NovaPay, Aurora, HeliosPay и кнопка загрузки
произвольного OpenAPI. Таблица строится из текущих fixtures/Blueprint данных:
auth, структура money, operations, webhook и extra operations различаются.

## 2. NovaPay spec-only — 10/14 и Review

Нажмите «Загрузить пример NovaPay — только OpenAPI». На Analysis/Review покажите
`10/14` автоматически принятых решений, оставшиеся вопросы и отсутствие
автоматической готовности всей спецификации. Это официальный/reference
OpenAPI без provider defaults.

Покажите, что evidence содержит `POST /payouts`,
`GET /payouts/{payout_id}` с operationId `getPayoutStatus`, а `/balance`
сохранён как неблокирующий `EXTRA_OPERATION`.

## 3. Money Review — факт, предложение и решение человека

Откройте money decision. Разделите на экране:

- evidence провайдера о единице и subunit;
- предложение analyzer;
- значение, которое подтверждает человек.

Для NovaPay host `operation.amount` — major RUB, provider amount — minor
kopecks, request conversion — `×100`. `Idempotency-Key` имеет
`required: false` в OpenAPI; отправка переданного ключа — `ADAPTER_POLICY`,
а не `SPEC_FACT`.

## 4. Resolved NovaPay — Preview

Нажмите подтверждённый пример NovaPay и откройте Preview:

```text
SPACE PAYMENTS INPUT
operation.amount = 1500.50 RUB
operation.payout_requisite["sbp"]["phone"] = 79001234567
request_method = sbp  (логический способ выплаты)
        ↓
BLUEPRINT TRANSFORMATION
        ↓
PROVIDER REQUEST
POST /payouts
recipient.type = sbp; recipient.phone = 79001234567

1500.50 RUB → provider amount 150050 kopecks
completed → approved → approve_operation
```

Покажите request, response/status и completed webhook с
`X-NovaPay-Signature`, `HMAC-SHA256`, raw body и hex. Объясните, что
`request_method=sbp` — логический host method, а `POST /payouts` — provider
HTTP transport.

Provider response id нормализуется в `success(result: { id: ... })`. Provider id
сохраняется платформой Space Payments; generated service не владеет persistence
операции или её состоянием.

Для status preview покажите также границу действий:

```text
completed → approved → approve_operation
failed    → rejected → reject_operation
pending/processing → in_progress → terminal helper не вызывается
```

Для callback отдельно проговорите: подпись считается по исходному `raw body`.
Система не пересобирает JSON для HMAC; если raw body отсутствует, проверка
должна завершаться fail-closed.

## 5. Generation — artifacts и обязательные проверки

Нажмите Generate. В каталоге результата создаётся следующий набор generated artifacts:

```text
service.rb
INTEGRATION.md
fixtures.json
provider_blueprint.json
review_manifest.json
contract_smoke.rb
INTEGRATION_READINESS.md
integration_readiness.json
```

В Generate page покажите `HTTP transport`: `PASS`, `localhost HTTP E2E`,
`Create request: PASS`, `Status request: PASS` и
`External provider call: NOT EXECUTED`. Это actual verification state, а не
статический label. Canonical `examples/novapay/` содержит этот набор и копию
входного `provider_api.yaml`; актуальное количество фиксируется generated
capabilities block в README.

## 6. Other OpenAPI — Aurora и HeliosPay

Откройте Aurora и HeliosPay из Home. Это synthetic provider fixtures для
independent validation, не production providers.

Покажите контраст:

| Case | Что показать |
|---|---|
| Aurora | Bearer header, nested `money.value`, `/transfers`, `/notifications`, four status mappings |
| HeliosPay | API key query, nested payment/settlement money, HTTP `202`, `Retry-After`, extra operation |

Aurora проходит `3/3` levels, HeliosPay — `2/2`. `12/12` относится к frozen
black-box cases, а не к числу провайдеров.

## 7. HTTP transport

После Generate откройте readiness или technical details. Проверка выполняет:

```text
generated adapter
  → provider base_url из runtime config
  → реальный localhost HTTP socket
  → captured create/status request
  → method/path/query/auth/body/content type
  → response parsing и status mapping
```

Реальный внешний sandbox не запускается: для него нет endpoint и credentials.
Не называйте localhost E2E live provider integration.

## Объяснение за 20 секунд

«Provider Compiler берёт OpenAPI платёжного провайдера, отделяет факты от
семантических выводов, показывает provenance и Review, а затем после разрешения
критических вопросов детерминированно генерирует Ruby adapter. В отличие от
обычного OpenAPI Generator он проверяет payment-domain mapping: деньги,
статусы, auth, webhook, idempotency и safety. Неоднозначность не угадывается,
а внешний provider sandbox в этом prototype не вызывается».

## Если UI не запускается

Проверьте `ruby --version` (`>= 3.3`), выполните `bundle install` и убедитесь,
что порт `4567` свободен. Можно сразу использовать CLI fallback:

```powershell
ruby bin/provider_compiler inspect
ruby bin/provider_compiler analyze
ruby bin/provider_compiler generate --out tmp/demo-generated
ruby bin/provider_compiler verify --out tmp/demo-generated
```

Для произвольного входа укажите явно `--spec`, `--profile` и при необходимости
`--defaults`. `analyze` создаёт только Blueprint и Manifest; runtime artifacts
появляются после успешной validation в `generate`.

## Фразы, которые нельзя перепутать

- `10/14` — semantic decisions, не endpoints.
- `37/37` — mutation cases, не providers.
- `12/12` — frozen black-box cases, не providers.
- localhost HTTP E2E ≠ external live provider.
- resolved NovaPay = OpenAPI + confirmed rules.
- Review ≠ failure; это fail-closed safety gate.
- `request_method` ≠ HTTP method.
- Provider Blueprint = source of truth.
- Generated Ruby = deterministic projection.
