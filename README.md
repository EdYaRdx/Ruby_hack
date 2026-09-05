# Provider Compiler

> OpenAPI → evidence-backed Provider Blueprint → verified Ruby adapter

Provider Compiler принимает OpenAPI платёжного провайдера, сопоставляет
provider-specific API с контрактом Space Payments, формирует `Review Manifest` и
`Resolved Provider Blueprint`, а затем детерминированно генерирует Ruby adapter,
документацию и fixtures. Критическая неоднозначность не угадывается: система
переходит в `REVIEW_REQUIRED` / `BLOCKING` и запрещает unsafe generation.

| | |
|---|---|
| Вход | OpenAPI YAML / JSON |
| Выход | Ruby adapter + `INTEGRATION.md` + `fixtures.json` |
| Target contract | `Provider::BaseService` |
| Decision model | `ACCEPT` / `REVIEW_REQUIRED` / `UNKNOWN` |
| Safety | critical ambiguity → generation blocked |
| Runtime | Ruby, deterministic, no neural networks |

## Проблема

Space Payments регулярно подключает новых платёжных провайдеров. Ручная
интеграция включает чтение документации, сопоставление endpoints и полей,
money conversions, статусы, auth, webhooks, idempotency, ошибки, Ruby adapter,
fixtures и integration docs; один provider занимает примерно 2–5 дней.

Обычный OpenAPI codegen автоматизирует HTTP boilerplate, но не отвечает на
главный вопрос: как provider-specific API отображается на payment-domain
contract Space Payments. Именно это mapping, а не создание HTTP-классов, является
центральной задачей Provider Compiler.

## Чем отличается от OpenAPI Generator

Обычный OpenAPI codegen:

```text
OpenAPI
  → API client / SDK
```

Provider Compiler:

```text
OpenAPI
  → facts
  → payment semantics
  → evidence / review
  → Provider Blueprint
  → verified Provider::BaseService adapter
```

| | OpenAPI Generator | Provider Compiler |
|---|---|---|
| HTTP client | Да | Да, как часть adapter |
| Payment semantics | Нет | Да |
| Status mapping | Обычно нет | Да |
| Money units | Обычно нет | Да |
| Review ambiguous semantics | Нет | Да |
| Fail-closed generation | Нет | Да |
| `Provider::BaseService` adapter | Нет | Да |

Provider Compiler не позиционируется как generic SDK generator: его результатом
является проверяемая проекция provider API на конкретный host contract.

## Как работает

1. OpenAPI читается и нормализуется; local `$ref` разрешаются до анализа.
2. Immutable `Facts IR` сохраняет факты входного документа без semantic guesses.
3. Independent analyzers строят решения для operations, money, auth, fields,
   statuses, webhooks, idempotency, constraints и errors.
4. Evidence и provenance попадают в `Review Manifest` вместе с rationale,
   conflicts и outcome.
5. Resolved decisions формируют `Provider Blueprint` — source of truth для
   generation.
6. Critical ambiguity переводит pipeline в fail-closed состояние.
7. Deterministic Generator создаёт Ruby adapter и сопутствующие артефакты.
8. Verification проверяет generated output.

## Архитектура

```mermaid
flowchart TD
    A["OpenAPI specification"] --> B["Spec Ingestion"]
    B --> C["Immutable Facts IR"]
    D["BaseServiceProfile"] --> E["Integration Analyzers"]
    F["Case Defaults / Overrides"] --> E
    C --> E
    E --> G["Evidence Ledger"]
    G --> H["Review Manifest"]
    H --> I{"Critical ambiguity?"}
    I -->|Yes| J["Human Review / Resolution"]
    I -->|No| K["Resolved Provider Blueprint"]
    J --> K
    K --> L["Blueprint Validation"]
    L --> M["Deterministic Generator"]
    M --> N["Ruby Provider Service"]
    M --> O["INTEGRATION.md"]
    M --> P["fixtures.json"]
    M --> Q["contract_smoke.rb"]
    N --> R["Verification"]
    O --> R
    P --> R
    Q --> R
    R --> S["Integration Ready"]
```

Слои намеренно разделены:

- `Spec Ingestion` — YAML/JSON, OpenAPI validation, local `$ref` resolving и
  fingerprint исходного closure;
- `Facts IR` — immutable набор фактов, без semantic guesses;
- `Analyzers` — provider-to-host mapping и safety decisions;
- `Review Manifest` — почему принято решение: evidence, provenance, rationale,
  conflicts и outcome;
- `Provider Blueprint` — что именно будет сгенерировано;
- `Generator` — как это будет выражено в deterministic Ruby projection, без новых
  semantic decisions;
- `Verification` — проверка generated output.

### Review Manifest vs Provider Blueprint

```mermaid
flowchart LR
    A["OpenAPI fact"] --> B["Analyzer"]
    B --> C["Review Manifest - WHY"]
    C --> D["Resolved Blueprint - WHAT"]
    D --> E["Generated Ruby - HOW"]
```

`Review Manifest` отвечает: «почему принято это решение?». `Provider Blueprint`
отвечает: «какой должна быть интеграция?». Generated Ruby отвечает: «как это
исполняется?». Generated Ruby не является source of truth: им остаётся resolved
Blueprint, а provenance решения сохраняется в Manifest.

### Core invariants

- `FACT` не равен `INFERENCE`; Facts IR immutable.
- Semantic decisions не живут в templates.
- Resolved Blueprint — source of truth, generated Ruby — projection.
- Critical semantics fail closed; каждое решение имеет provenance.
- Unknown provider information сохраняется и показывается.
- CLI и Web используют один Application/Core pipeline.
- Provider-specific assumptions не попадают в generic core.

## Fail Closed

Например, если в спецификации есть только:

```yaml
amount:
  type: integer
```

но не указано, используются ли major или minor units, какой scale и какова
currency semantics, система не выбирает молча `×100` или `÷100`. Результат —
`REVIEW_REQUIRED`, `BLOCKING`, generation unavailable. Для критической финансовой
семантики система предпочитает безопасную остановку потенциально неверной
генерации.

## Автоматически обновляемый снимок возможностей

Снимок возможностей ниже генерируется из checkout проекта, canonical example и
результатов проверок. Он обновляется командой `bin/update_docs`.

<!-- BEGIN GENERATED: CAPABILITIES -->
- Загрузка и проверка OpenAPI, локальные references и source fingerprinting: присутствует `lib/provider_compiler/core.rb`.
- Анализ с учётом evidence, Review Manifest и Provider Blueprint: реализации analyzer/profile/blueprint присутствуют.
- Детерминированная Ruby-проекция и verification: реализация generator присутствует.
- Канонический пример NovaPay: 7 файлов в `examples/novapay/` (`INTEGRATION.md`, `contract_smoke.rb`, `fixtures.json`, `provider_api.yaml`, `provider_blueprint.json`, `review_manifest.json`, `service.rb`).
- Независимая semantic validation: benchmark NovaPay и сравнение Aurora входят в сгенерированный статус выше.
- Live provider calls не реализованы; Web UI Demo Workbench реализован в `lib/provider_compiler/web.rb`, `lib/provider_compiler/web_renderer.rb` и `web/public/`.

Для обновления снимка запустите `ruby bin/update_docs`.
<!-- END GENERATED: CAPABILITIES -->

## CLI

Требуется Ruby >= 3.0. Текущий checkout проверен на Ruby 4.0.6 и Bundler 2.5.22.

```powershell
bundle install
bundle exec rspec
ruby -c lib/provider_compiler.rb
ruby bin/provider_compiler inspect
ruby bin/provider_compiler analyze
ruby bin/provider_compiler generate --out tmp/generated
ruby bin/provider_compiler verify --out tmp/generated
```

`inspect` выводит decision summary, `analyze` создаёт артефакты без отдельного
финального запуска Blueprint validation, а `generate` выполняет validation перед
generation. `verify` принимает каталог generated output и запускает Ruby syntax
checks и `contract_smoke.rb`.

Для другого провайдера используются явные входы:

```powershell
ruby bin/provider_compiler generate `
  --spec path/to/provider.yaml `
  --profile profiles/space_payments_v1.yml `
  --defaults path/to/provider_defaults.yml `
  --out tmp/provider
```

Профили и case defaults остаются входами конкретного кейса, а provider-specific
assumptions не зашиваются в generic analyzer-код. Вместо `--out` можно передать
реальный alias `--output`; `PROVIDER_SPEC` задаёт spec по умолчанию.

## Эталонный пример NovaPay

Воспроизводимый источник —
[`fixtures/novapay_provider_api.yaml`](fixtures/novapay_provider_api.yaml).
Каноническая сгенерированная проекция поддерживается командой
`bin/update_examples` в каталоге [`examples/novapay/`](examples/novapay/).
SHA-256 официального reference input:
`415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551`.

Эталонный кейс показывает:

- `POST /payouts` -> `create_request`;
- `GET /payouts/{payout_id}` -> `fetch_status`, operationId
  `getPayoutStatus`;
- sandbox base URL из официальной спецификации: `https://api.sandbox.novapay.example/v1`;
- `operation.amount` хоста как major RUB и amount провайдера как minor kopecks;
  request conversion — `major -> minor` с factor `100`;
- необязательный по OpenAPI `Idempotency-Key`; по умолчанию адаптер отправляет
  переданный ключ (`if_available`), а `--always-send-idempotency` — явная политика
  адаптера, не факт спецификации;
- `/balance` сохраняется как неблокирующий `EXTRA_OPERATION`;
- webhook `payout.completed` с `X-NovaPay-Signature`, HMAC-SHA256, raw body и
  hex encoding;
- mapping provider status `completed` → `approved`;
- webhook event `payout.completed` → `approved` → callback action
  `approve_operation`.

End-to-end пример для `1500.50 RUB`:

```text
Space Payments operation.amount: 1500.50 RUB
  → major_to_minor ×100
NovaPay request.amount: 150050 kopecks

NovaPay status: completed
  → Space Payments status: approved
  → callback action: approve_operation
```

`GET /balance` не становится canonical `BaseService` operation без основания: он
сохраняется как `EXTRA_OPERATION` и остаётся неблокирующим.

## Что генерируется

Команда `generate` создаёт шесть файлов в output directory:

```text
tmp/generated/
├── service.rb
├── INTEGRATION.md
├── fixtures.json
├── provider_blueprint.json
├── review_manifest.json
└── contract_smoke.rb
```

- `service.rb` — generated `Provider::BaseService` adapter;
- `INTEGRATION.md` — настройка и использование интеграции;
- `fixtures.json` — request/response/webhook examples;
- `provider_blueprint.json` — resolved integration contract;
- `review_manifest.json` — evidence и decisions;
- `contract_smoke.rb` — executable runtime smoke test.

Канонический `examples/novapay/` дополнительно хранит копию входного
`provider_api.yaml`, поэтому там семь файлов. Generated artifacts следует
пересоздавать из fixture/profile/defaults, а не редактировать вручную.

## Web UI

Локальный Demo Workbench показывает тот же pipeline, не меняя семантику
компилятора:

```powershell
bundle exec ruby bin/provider_compiler_web
```

Откройте `http://127.0.0.1:4567` и пройдите flow
«Загрузка» → «Анализ» → «Review» → «Preview» → «Generate». На экране анализа
видны endpoints, canonical operations, auth, money, statuses, webhook,
idempotency, field mappings, constraints, errors и evidence. Review показывает
решения Manifest и их основания; Preview выполняет request/response/webhook
projections на fixture-данных; Generate показывает артефакты и Verification.

На стартовом экране доступны NovaPay, неоднозначный money-case и Aurora. UI не
выполняет реальных сетевых вызовов к provider.

## Что система анализирует

| Область | Пример |
|---|---|
| Operations | `POST /payouts` → `create_request` |
| Authentication | `X-API-Key` |
| Money | `major` → `minor` ×100 |
| Fields | `operation.amount` → `request.amount` |
| Statuses | `completed` → `approved` |
| Webhooks | `HMAC-SHA256` |
| Idempotency | `Idempotency-Key` |
| Constraints | `required` / `minimum` / `enum` |
| Errors | `400` / `401` / `409` / `422` / `429` / `500` |
| Extras | `/balance` preserved as `EXTRA_OPERATION` |

## Verification

`Verification` проверяет только существующие в реализации gates: наличие
generated `service.rb` и `contract_smoke.rb`, Ruby syntax для обоих файлов и
успешное выполнение contract smoke. Сам smoke проверяет request projection,
money conversion, sandbox URL, response/status mapping и webhook behavior на
fixture-данных.

## Universality и benchmark

Универсальность здесь означает переносимость generic pipeline на покрытые
provider shapes, а не поддержку любого OpenAPI. Проверка состоит из NovaPay
reference case, 37 independently materialized mutation scenarios с hand-authored
semantic ground truth и independent comparator, а также второго synthetic
provider Aurora с другой структурой API.

Aurora проверяет другой endpoint naming, Bearer auth, nested `money.value`,
`money.currency`, destination, `POST /notifications`, собственные status enums и
preserved extra operations. Для него отдельно заданы semantic levels и
behavioral vectors; decision equality сама по себе не считается доказательством.

Подробная методика и определения метрик находятся в
[`docs/BENCHMARK.md`](docs/BENCHMARK.md), а материалы независимой проверки — в
[`research/SEMANTIC_BENCHMARK_VALIDATION.md`](research/SEMANTIC_BENCHMARK_VALIDATION.md)
и [`research/SECOND_PROVIDER_VALIDATION.md`](research/SECOND_PROVIDER_VALIDATION.md).

## Статус проверки

Следующий блок генерируется `bin/update_docs` на основе реальных benchmark
runner-ов и текущего запуска RSpec. Числа не копируются вручную.

<!-- BEGIN GENERATED: PROJECT_STATUS -->
**Текущая проверка (сгенерировано автоматически)**

- RSpec: 63 examples, failures: 0.
- Mutation benchmark NovaPay: безопасно пройдено 37/37; decision_accuracy: 100.0%; safe_decision_coverage: 100.0%.
- automatic_accept_rate: 48.6%; review_required_rate: 40.5%; unknown_rate: 10.8%.
- semantic_accept_accuracy: 100.0%; critical_false_accept_count: 0.
- Aurora: levels 3/3, behavioral vectors 4/4; semantic_accuracy: 100.0%.

Для обновления блока запустите `ruby bin/update_docs`.
<!-- END GENERATED: PROJECT_STATUS -->

Регрессионное покрытие UI находится в [`spec/web_spec.rb`](spec/web_spec.rb).

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — текущая архитектура и
  инварианты;
- [`docs/BENCHMARK.md`](docs/BENCHMARK.md) — методика, формулы и актуальные
  результаты;
- [`docs/DEMO.md`](docs/DEMO.md) — готовый live-сценарий для Web UI, fail-closed,
  Aurora и CLI fallback;
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — процесс разработки и проверок;
- [`docs/DOCS_POLICY.md`](docs/DOCS_POLICY.md) — правила для стабильной и
  generated-документации;
- [`docs/GLOSSARY.md`](docs/GLOSSARY.md) — единый словарь терминов;
- [`THIRD_PARTY.md`](THIRD_PARTY.md) — зависимости и лицензии;
- [`research/README.md`](research/README.md) — supporting research и audit
  artifacts с явным разделением текущих и исторических материалов.

## Repository structure

```text
bin/                    CLI, Web entrypoint и детерминированные updater-ы
lib/provider_compiler/  Facts IR, analyzers, Blueprint, generation, Web/API
profiles/               BaseServiceProfile для host-контракта
fixtures/               OpenAPI, case defaults и независимая Aurora ground truth
examples/               сгенерированные и проверяемые provider projections
spec/                   RSpec regression, semantic и Web UI проверки
research/               benchmark corpus, comparator и исторические материалы
docs/                   актуальная engineering и judge-facing документация
```

## Limitations

Это research/hackathon prototype, а не SaaS и не заявление о поддержке любого
провайдера. Production `Provider::BaseService` в репозитории не предоставлен:
для verification используется local stub/harness. Live provider calls, production
credentials и deployment не входят в scope.

Для нового provider могут потребоваться явные profile, case defaults и human
review полученного Manifest. Remote `$ref` не поддерживаются и отклоняются;
некоторые provider semantics остаются `REVIEW_REQUIRED` или `UNKNOWN`, пока не
появятся достаточные evidence и resolution.

## Hackathon compliance

Ruby share проходит требование `>50%` согласно текущему repository audit. Core
functionality не зависит от proprietary runtime service: dependencies —
open-source gems, generated output не требует внешнего inference service, а
runtime работает детерминированно и без нейросетевых моделей.

## Безопасность и соответствие ограничениям

Спецификации обрабатываются локально; UI не сохраняет production credentials и
не выполняет вызовы провайдера. Неизвестная или критически неоднозначная
семантика сохраняется в `Review Manifest` и не превращается молча в `ACCEPT`.
Source fingerprint включает root document, resolved local inputs и resolver
policy.

Для расширения системы используйте [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)
и соблюдайте инварианты безопасности из
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
