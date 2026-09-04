# Независимое архитектурное предложение

> **ИСТОРИЧЕСКОЕ ПРЕДЛОЖЕНИЕ.** Это design research, а не отдельный runtime
> contract. Реализованная архитектура описана в [`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md).

## От первых принципов

Проблема не в том, чтобы «генерировать Ruby из каждой возможности OpenAPI».
Ценная задача — преобразовать contract provider-а в безопасный adapter для
небольшого canonical payment contract, который можно проверить на review.
OpenAPI хорошо описывает shapes и хуже — некоторые business semantics.
Архитектура должна сохранять эту асимметрию.

Независимый выбор — **E: profiled evidence-gated compiler**:

```text
Spec
  -> Ingest + validate + fingerprint
  -> Facts IR
  -> Candidate analyzers
  -> Evidence ledger
  -> Review Manifest
  -> Apply fresh scoped decisions
  -> Blueprint v1
  -> deterministic projections
  -> verification workspace
```

E намеренно меньше полного proposal D. В нём нет Web UI, automatic rule
learning, database и runtime semantic inference в ERB. Взаимодействие с user
строится вокруг стабильного file/CLI contract, который позже может стать основой
UI.

## Компоненты и ownership

| Component | Owns | Must not own |
|---|---|---|
| Ingestor | YAML/JSON load, dialect/version, source hash, parser errors | payment meaning |
| Validator/Resolver | OpenAPI/schema validation, internal/local refs | operation roles |
| Structural IR | immutable facts with JSON pointers and raw evidence | inferred conversions |
| BaseServiceProfile | target method signatures, host fields/helpers and stub contract | provider-specific mappings |
| Analyzers | candidates and evidence for one semantic concern | Ruby templates or other analyzer decisions |
| Evidence ledger | source, score, margin, conflicts, provenance | probability claims |
| Review Manifest | unresolved decisions, action, severity and user-facing rationale | generated service source |
| Override applier | fresh, scoped human decisions | rewriting structured spec facts |
| Blueprint builder | resolved integration model and validation | hidden inference |
| Projections | Ruby, docs, fixtures, readiness report | semantic guessing |
| Verification workspace | stub contract, fixtures, snapshots, mutation execution | production credentials/network |

## Почему facts-only IR обязателен

Один и тот же текст может быть полезным evidence, но не доказанным invariant.
Например, `amount: integer` — structural fact, «amount in kopecks» — declaration
в description, а `multiply_100` — target-specific transformation. Хранение этих
сведений в отдельных fields не позволяет template случайно принять inference за
fact.

Suggested `OperationIR`:

```text
OperationIR
  source_pointer, method, path, operation_id
  tags, summary, description
  parameters[], request_bodies[], response_variants[]
  security_requirements[], callbacks[], webhooks[]
  schemas and examples as resolved source nodes
```

Каждое value содержит source pointer. Analyzer может сослаться на description,
но IR никогда не хранит `amount_unit: minor`.

## Граница BaseServiceProfile

Case предоставляет method names и illustrative code, а не гарантированный
production class. Profile делает эту неопределённость явной:

```yaml
profile_version: 1
class_name: Provider::BaseService
service_name_pattern: Provider::<Name>Service
methods:
  - name: check_conditions
    signature: (operation, request_method)
  - name: create_request
    signature: (operation, request_method)
  - name: process_callback
    signature: (payload)
  - name: fetch_status
    signature: (operation)
request_method:
  kind: logical_action
  values: [create, status, check, cancel]
operation_fields: [amount, id, provider_operation_id, payout_requisite]
helpers: [success, failure, approve_operation, reject_operation, client]
```

Приведённые значения profile имеют статус `CASE_ASSUMPTION`, пока не будет
предоставлен реальный contract. Stub реализует только объявленные methods/helpers.
Generator не должен вызывать undeclared private helper. Когда реальный contract
будет предоставлен, сначала обновляются profile и contract tests.

Поэтому `request_method` — logical action token, а не HTTP method provider-а.
HTTP `POST` относится к endpoint binding, а `create` — к host profile/action
dispatch.

## Review-first data model

Analyzers выдают candidates, а не final integration. Review Manifest группирует
их как `accepted`, `review_required`, `unknown` и `blocking`. Human decision
фиксирует who/when, выбранный candidate, rationale и source fingerprint. Только
validated resolved manifest может создать Blueprint.

Это надёжнее, чем размещать `Human Review / Overrides` после уже resolved
Blueprint: unresolved decisions видны до того, как их можно принять за generated
truth.

## Независимое сравнение альтернатив

| Variant | Strength | Fatal weakness | Decision |
|---|---|---|---|
| A direct templates | fastest demo | semantics hidden in templates; poor testability | reject |
| B IR -> Ruby | clean shape preservation | no explicit critical uncertainty boundary | reject as final |
| C IR -> analyzers -> Blueprint -> Ruby | good separation and explainability | assumes review/profile details are already solved | base direction |
| D full proposal with UI/rules | rich UX and accumulation | too broad for solo MVP; precedence/staleness underspecified | narrow |
| **E profiled evidence-gated compiler** | same safety with explicit host profile and file review | more deliberate schema design | **choose** |

## Проверка market/analogues

Релевантный analogue — не competitor, который делает задачу ненужной. OpenAPI
Generator явно разделяет normalized API model, transformation logic и templates;
его official docs также отмечают, что одних templates недостаточно для advanced
transformations. Следует заимствовать это разделение, но не его широкий
multi-language scope: [templating](https://openapi-generator.tech/docs/templating/),
[customization](https://openapi-generator.tech/docs/customization/).

Payment documentation reinforces two patterns: idempotency — explicit request
contract, а webhook verification должна использовать original raw body
provider-а. Stripe документирует и [idempotent requests](https://docs.stripe.com/api/idempotent_requests),
и [raw-body signature verification](https://docs.stripe.com/webhooks/signature);
Adyen описывает HMAC как механизм webhook integrity в [secure webhooks
guidance](https://docs.adyen.com/development-resources/webhooks/secure-webhooks/).
Это patterns для evidence fields, а не разрешение выводить policy одного
provider-а из документации другого.

### Ruby OSS building blocks

Implementation может оставаться преимущественно Ruby без изобретения parser stack:

- [`openapi_first`](https://github.com/ahx/openapi_first) — Ruby OpenAPI
  request/response validation layer и candidate для ingest boundary;
- [`json_schemer`](https://github.com/davishmcclurg/json_schemer) полезен для
  JSON Schema validation и reference resolution;
- [`openapi3_parser`](https://github.com/kevindew/openapi3_parser) и
  [`openapi_parser`](https://github.com/ota42y/openapi_parser) — альтернативные
  OAS parser candidates, требующие real compatibility spike;
- Ruby stdlib [`ERB`](https://github.com/ruby/erb) и [`OptionParser`](https://github.com/ruby/optparse)
  достаточны для deterministic templates и небольшого CLI, а
  [`RSpec`](https://github.com/rspec/rspec) может предоставить generated contract tests.

Это candidate dependencies, а не verified choices: на момент подготовки этого
research workspace ещё не имел usable Ruby runtime/bundle, поэтому license,
version, external-ref behavior и performance требовали implementation spike.
Текущая реализация использует зафиксированный Ruby toolchain; architecture не
должна делать internal model какой-либо одной library публичным Blueprint.

## Предлагаемая итоговая diagram

```text
              +----------------------+
provider spec | Ingest / validate    |  source fingerprint
--------------> resolve refs         +------------------+
              +----------+-----------+                  |
                         v                              |
              +----------------------+                   |
              | Facts-only IR       |                   |
              +----------+-----------+                   |
                         v                               |
              +----------------------+                   |
              | Analyzers + evidence |                   |
              +----------+-----------+                   |
                         v                               |
              +----------------------+  overrides       |
              | Review Manifest     |<------------------+
              +----------+-----------+
                         v
              +----------------------+  BaseServiceProfile
              | Blueprint v1        |<------------------+
              +----+-----------+-----+                   |
                   |           |                         |
             Ruby service  docs/fixtures            verification
                   |           |                         |
                   +-----------+-------------------------+
```
