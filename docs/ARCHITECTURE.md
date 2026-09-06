# Текущая архитектура Provider Compiler

Документ описывает реализацию текущего checkout. Он не содержит исторических
планов и не является обещанием поддержки любого OpenAPI или production host
contract.

## Назначение и граница системы

Provider Compiler принимает локальный OpenAPI YAML/JSON, `BaseServiceProfile` и
необязательные явно переданные `CaseDefaults`/Review overrides. Он извлекает
provider facts, сопоставляет их с контрактом Space Payments, сохраняет
доказательства и генерирует детерминированную Ruby projection только после
проверки критической семантики.

Система локальная и детерминированная. В ней нет моделей машинного обучения,
удалённого inference service, базы данных или автоматического live-вызова
внешнего provider.

## Конвейер

```text
OpenAPI
  ↓
Spec Ingestion
  ↓
Immutable Facts IR
  ↓
Analyzers
  ↓
Evidence Ledger
  ↓
Review Manifest
  ↓
Human-confirmed resolutions
  ↓
Resolved Provider Blueprint
  ↓
Blueprint Validation
  ↓
Deterministic Generator
  ↓
Artifacts
  ↓
Verification
```

## Граница host operation и provider request

В текущем profile преобразование имеет явную границу:

```text
Space Operation
  → Host Projection
  → Canonical Blueprint data
  → Provider request
```

`operation.payout_requisite` — это представление реквизитов на стороне host.
Внутренний canonical recipient и provider body могут иметь другую форму:
например, `operation.payout_requisite["sbp"]["phone"]` становится полем
provider `recipient.phone`. Поэтому generated adapter не должен выводить
наличие flat top-level `operation.recipient_phone` из provider schema.

Нужно различать три независимых понятия:

| Понятие | Пример | Что означает |
|---|---|---|
| BaseService operation | `create_request` | метод host adapter contract |
| host logical `request_method` | `sbp` / `card` | способ выплаты и выбор requisite branch |
| provider transport | `POST /payouts` | HTTP method и path конкретного API |

`request_method != HTTP method != create_request`. `/balance` и другие
непривязанные endpoint-ы сохраняются как `EXTRA_OPERATION` и не становятся
canonical BaseService operation без явного profile binding.

### Роли слоёв

| Слой | Ответственность |
|---|---|
| `Spec Ingestion` | загрузка YAML/JSON, валидация OpenAPI, разрешение локальных `$ref`, source fingerprint |
| `Facts IR` | неизменяемая нормализованная запись того, что присутствует во входе |
| `Analyzers` | операции, auth, money, поля, статусы, webhook, idempotency, constraints и errors |
| `Evidence Ledger` | provenance, locations, excerpts, confidence и источники решений |
| `Review Manifest` | объясняет `WHY`: решения, доказательства, конфликты и unresolved items |
| `Provider Blueprint` | фиксирует `WHAT`: выбранные endpoint-ы, mapping, policy и runtime contract |
| `Blueprint Validation` | проверяет, что resolved Blueprint безопасен для генерации |
| `Generator` | выражает Blueprint как Ruby adapter и документацию; новых semantic решений не принимает |
| `Verification` | проверяет syntax, contract smoke и фактический localhost HTTP transport |

Главный инвариант: `FACT != INFERENCE`. `Review Manifest` — это **WHY**,
`Provider Blueprint` — **WHAT**, generated Ruby — **HOW**.

## Реализация по каталогам

- `lib/provider_compiler/core.rb` — ingestion, local refs, immutable facts и fingerprint;
- `lib/provider_compiler/profile.rb` — `BaseServiceProfile` и host contract;
- `lib/provider_compiler/analysis.rb` — analyzers, evidence, precedence и safety decisions;
- `lib/provider_compiler/blueprint.rb` — Blueprint, Manifest projection и validation;
- `lib/provider_compiler/generation.rb` — deterministic Ruby projection и syntax/smoke verification;
- `lib/provider_compiler/transport_verification.rb` — local HTTP socket verification generated adapter;
- `lib/provider_compiler/application.rb` — общий orchestration для CLI;
- `lib/provider_compiler/web.rb` и `web_renderer.rb` — тонкий Web UI adapter над тем же pipeline;
- `profiles/` — host profiles;
- `fixtures/` — reproducible OpenAPI, defaults, ground truth и behavioral vectors;
- `examples/` — generated reference artifacts;
- `spec/` — unit, integration, UI и safety regression tests.

## Источники знаний и precedence

OpenAPI — основной источник provider facts. Profile описывает canonical host
contract. `CaseDefaults` и Review overrides — отдельные, явно переданные знания
конкретного кейса; они не выводятся из имени provider или файла и не становятся
глобальными facts.

Локальные `$ref` разрешаются до анализа. Fingerprint включает root document,
разрешённые local input refs и resolver policy. Поэтому изменение подключённого
файла не может незаметно использовать старые persisted decisions.

## Persisted Review

```text
human decision
  ↓
HUMAN_CONFIRMED
  ↓
provider_overrides.yml
  ↓
spec fingerprint/profile validation
  ↓
reuse OR stale rejection
```

Экспортируются только подтверждённые решения. При применении проверяются
fingerprint спецификации, root hash, profile/version, decision ids и отсутствие
credential-like полей. Изменившаяся спецификация или несовместимый profile
отклоняют старый override; тихого переноса решений нет. CLI и Web UI используют
один формат persisted Review.

## Решения и fail-closed safety

| Decision | Смысл | Поведение |
|---|---|---|
| `ACCEPT` | достаточные доказательства для обязательной семантики | Blueprint допускается к validation/generation |
| `REVIEW_REQUIRED` | значимая неоднозначность требует человека | evidence сохраняется; `BLOCKING` запрещает generation |
| `UNKNOWN` | information unsupported или mapping не восстановим | item сохраняется и сообщается; скрытого mapping нет |

Endpoint-ы, которые не объявлены canonical в profile, сохраняются как
неблокирующие `EXTRA_OPERATION`. В частности, `/balance` не становится
canonical `BaseService` operation без явного profile binding.

Provider facts и adapter policy разделяются. Например, optional
`Idempotency-Key` остаётся `SPEC_FACT` с `required: false`, а решение отправлять
переданный ключ — `ADAPTER_POLICY`.

## Runtime transport boundary

```text
Generated adapter
  ↓
Outbound HTTP
  ↓
Provider base_url из runtime config
  ↓
Auth
  ↓
Request serialization
  ↓
Response / status / error handling
```

`TransportVerification` поднимает ephemeral localhost provider, загружает
generated adapter, задаёт runtime Base URL и отправляет реальный socket request
через `Net::HTTP`. Captured request проверяется по method/path/query/auth/body и
`Content-Type`; status request проверяется по method/path parameter/auth; затем
проверяются response parsing и canonical status mapping.

Это различает три утверждения:

1. outbound HTTP transport implemented — **да**;
2. executable verification через localhost HTTP — **да**;
3. external provider sandbox executed — **нет**, endpoint/credentials не заданы.

Результат сохраняется как `runtime_transport` в readiness JSON/Markdown и
показывается на Generate page. Локальная проверка не является production
acceptance с реальным `Space Payments BaseService`.

## Web UI Demo Workbench

`lib/provider_compiler/web.rb` создаёт изолированное временное workspace на
каждую загрузку. `web_renderer.rb` и `web/public/` отвечают за presentation.
Workbench показывает NovaPay, Aurora, HeliosPay и arbitrary upload, но использует
тот же Application/Core pipeline, что и CLI. UI не содержит отдельного analyzer
или provider-name mapping engine.

## Архитектурные инварианты

- Facts IR неизменяем и отделён от inference;
- semantic decisions не живут в templates;
- Blueprint — источник истины для generated runtime;
- provenance и safety decision сохраняются в Manifest;
- unresolved critical semantics не генерируются молча;
- extra и unsupported information не теряются;
- provider-specific defaults не попадают в generic analyzer/core;
- CI и tests не вызывают внешний provider;
- generated artifacts воспроизводимы через updater commands.

## Ограничения

Remote `$ref`, OAuth2/cookie auth, сложные schema compositions и неизвестные
runtime host protocols не обещаются автоматически. Production
`Provider::BaseService` в checkout отсутствует, поэтому verification использует
profile-driven stub/harness. Для нового provider могут потребоваться явные
defaults, profile extension и human Review.

Подробные invariants: [`research/ARCHITECTURE_INVARIANTS.md`](../research/ARCHITECTURE_INVARIANTS.md).
Policy документации: [`docs/DOCS_POLICY.md`](DOCS_POLICY.md).
