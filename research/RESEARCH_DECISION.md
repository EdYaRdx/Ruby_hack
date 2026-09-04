# Исследовательское решение

Дата: 2026-09-03

> Это исходное исследовательское решение. После независимого red-team review
> оно superseded по scope и contract boundary файлами `FINAL_VERDICT.md`,
> `INDEPENDENT_ARCHITECTURE_PROPOSAL.md` и `CURRENT_ARCHITECTURE_AUDIT.md`.

## Решение в одном абзаце

Выбираем архитектуру **C: OpenAPI -> Structural IR -> payment-aware semantic
analyzers -> Provider Blueprint -> decision gate -> deterministic generator ->
verification**. Семантический подход — **rules + lexical aliases + schema /
structure + explainable evidence scoring + abstention**. Любое финансово-критичное
решение без явного evidence уходит в `REVIEW_REQUIRED`, а конфликт или
неразрешимая ссылка — в `UNKNOWN`. Это даёт почти максимальное покрытие без
опасных автоматических догадок и помещается в соло-MVP.

## Ответы на обязательные вопросы

1. **Архитектура.** C с единственным промежуточным `Provider Blueprint` и
   отдельным decision gate. Шаблоны получают только уже принятое blueprint-дерево.
2. **Semantic approach.** Гибридный детерминированный анализ: точные правила,
   ограниченные доменные aliases, структура схемы и evidence score. Fuzzy только
   как подсказка для review, не как источник `ACCEPT`.
3. **Реально нужные алгоритмы.** Нормализация OpenAPI, локальный `$ref` resolver,
   discovery операций, pointer-based field mapping, explicit unit detection,
   status taxonomy, auth/idempotency/webhook/error analyzers, top1-top2 margin,
   decision policy, deterministic ERB codegen и validation fixtures.
4. **Не нужны.** LLM, neural API, embeddings, TF-IDF, BM25, графовый lifecycle
   matcher, полноценная fuzzy-семантика, web UI, автогенерация сложных
   provider-specific методов и попытка «угадать» скрытые финансовые правила.
5. **Где REVIEW/UNKNOWN.** `REVIEW_REQUIRED`: aliases `amount -> sum`, новые
   terminal statuses, отсутствие единиц, отсутствие idempotency, подпись без
   алгоритма, условие из свободного текста. `UNKNOWN`: hard conflict,
   unresolved `$ref`, ambiguous operation, неподдерживаемый auth/webhook,
   конфликтующие evidence. При review сервис не генерируется как ACCEPTed
   production artifact без явного override.
6. **Provider Blueprint.** Версионируемый, сериализуемый объект — единственный
   source of truth для Ruby service, `INTEGRATION.md`, `fixtures.json` и
   diagnostics. Поля перечислены в ADR и в `EDGE_CASES.md`.
7. **Зависимости.** Для MVP предпочтительны `openapi_first` для contract/schema
   validation, `json_schemer` для JSON Schema/OpenAPI validation, Ruby stdlib
   `YAML`, `JSON`, `ERB`, `OptionParser`, плюс RSpec в development. Парсер и
   semantic layer остаются тонкими Ruby-модулями; не строим wrapper над большой
   библиотекой. `amatch`, `Thor`, второй OpenAPI parser не входят в MVP.
8. **Первый MVP.** Сначала parser/IR и golden NovaPay case; затем critical
   analyzers (money/auth/idempotency/status/webhook), Blueprint + decision gate;
   затем generator, docs/fixtures, CLI и verification.
9. **Benchmark targets.** На 37 mutation cases: `ACCEPT` precision >= 99%,
   critical false accepts = 0 по шести safety-классам, safe decision coverage
   >= 85%, operation mapping >= 90% на non-ambiguous cases, field/money >= 95%
   при explicit units и 100% generation syntax pass в Ruby CI.
10. **Expected score.** У C ожидается 95/100 технических баллов и около 113/120
    с отраслевым блоком при наличии diagnostics и убедительной демонстрации.
    Причина — оно одновременно показывает разбор, корректный generated service,
    универсальность и объяснимую безопасность; численная модель раскрыта в
    `EXPECTED_SCORE.md`.

## Проверка OSS (2026-09-03)

Проверялись только небольшие Ruby OSS-компоненты, которые могут сократить время
MVP. Лицензии и заявленная поддержка сверялись с официальными репозиториями:

| Компонент | Что подтверждено upstream | Решение |
|---|---|---|
| [`openapi_first`](https://github.com/ahx/openapi_first) | MIT; request/response validation и contract testing; README заявляет OpenAPI 3.0/3.1; gemspec требует Ruby >= 3.3 | взять для validation/contract layer, не отдавать ему semantic mapping |
| [`json_schemer`](https://github.com/davishmcclurg/json_schemer) | MIT; JSON Schema drafts 4/6/7/2019-09/2020-12 и OpenAPI 3.0/3.1; есть custom `ref_resolver` | взять для schema validation и fixtures |
| [`openapi3_parser`](https://github.com/kevindew/openapi3_parser) | MIT; object graph, external refs и validation для OpenAPI 3.0; upstream помечает проект work in progress и не обещает 3.1 | не брать в core, оставить fallback spike |
| [`openapi_parser`](https://github.com/ota42y/openapi_parser) | MIT; OpenAPI 3 parser/validator, strict reference validation option | не добавлять одновременно с `openapi_first`; сравнить только если первый не проходит fixture |
| [`amatch`](https://github.com/flori/amatch) | Apache-2.0; набор approximate matching алгоритмов через C extension | не брать: fuzzy не разрешает critical ACCEPT и не окупается в MVP |
| [`ERB`](https://github.com/ruby/erb) | Ruby project, 2-Clause BSD, входит в Ruby; предназначен в том числе для code generation | взять: достаточно для простых deterministic templates |
| [`OptionParser`](https://github.com/ruby/optparse) | Ruby standard-library CLI option parser | взять вместо Thor для одного последовательного CLI |
| [`Thor`](https://github.com/rails/thor) | MIT; self-documenting CLI toolkit, но добавляет отдельную зависимость | не брать на MVP: один `integrate` command покрывается stdlib |
| [`RSpec`](https://github.com/rspec/rspec) | MIT; core/expectations/mocks и `rspec` command | взять как development/test dependency для четырёх test layers |

Зависимости не закрывают semantic layer: operation roles, money units,
idempotency, status safety и webhook signatures всё равно реализуются небольшими
Ruby analyzers с evidence ledger.

## Reference case: ground truth

Из `provider_api.yaml` зафиксировано пять path/method operations:

| Operation | HTTP | Path | Auth | Назначение |
|---|---|---|---|---|
| `createPayout` | POST | `/payouts` | `ApiKeyAuth` header `X-API-Key` | создать выплату |
| `getPayoutStatus` | GET | `/payouts/{payout_id}` | тот же API key | получить статус |
| `cancelPayout` | POST | `/payouts/{payout_id}/cancel` | тот же API key | отменить выплату |
| `payoutWebhook` | POST | `/webhooks/payout` | `security: []` | принять webhook |
| `getBalance` | GET | `/balance` | тот же API key | баланс провайдера |

На create: JSON request с обязательными `amount`, `currency`, `external_id`,
`recipient`; optional `Idempotency-Key` header (`required: false` в OpenAPI).
`operation.amount` в Space Payments — major RUB, а provider `request.amount` —
minor/копейки: request conversion `×100`, response conversion `/100`. Это
разные evidence records для host и provider. Provider amount явно подтверждён
description и validation error; валюта — `RUB`. Если adapter всегда отправляет
опциональный header, это `ADAPTER_POLICY`, а не `SPEC_FACT`. Recipient:
`type` и `phone` обязательны, `bank_code` нужен для `type=sbp`, `card_number`
нужен для `type=card`, но эти два условия описаны текстом, а не JSON Schema
`oneOf`.

Response statuses: create `201`, `400`, `401`, `402`, `409`, `422`, `429`,
`500`; status read `200`, `401`, `404`; cancel `200`, `409`; webhook `200`;
balance `200`. `429` содержит `Retry-After` в секундах. Webhook подпись —
`X-NovaPay-Signature`, description explicitly says HMAC-SHA256. Status enum:
`pending`, `processing`, `completed`, `failed`, `cancelled`; direct mapping to
base contract follows the case description: `in_progress`, `approved`,
`rejected`.

## Стратегия codegen

Generated file должен использовать host contract:

```ruby
class Provider::NovapayService < Provider::BaseService
  def check_conditions(operation, request_method); end
  def create_request(operation, request_method = "create"); end
  def process_callback(payload); end
  def fetch_status(operation); end
end
```

Paths, field pointers, unit conversion, status/error maps и webhook settings
передаются из Blueprint. ERB только отображает уже принятые values; он никогда
не разбирает descriptions и не выбирает semantic role. Для каждого accepted
output запускаются `ruby -c`, generated fixture tests и smoke test
BaseService-contract.

## Стратегия тестирования

Обязательны четыре слоя:

1. **Parser tests** — YAML/JSON load, OpenAPI validation, internal and local
   external `$ref`, endpoint discovery and security discovery.
2. **Semantic mapping tests** — money units, status, auth, idempotency,
   Retry-After/errors, webhook shape/signature and conditional fields.
3. **Generated-code tests** — deterministic snapshots, class/method contract,
   `ruby -c`, generated service load and request construction.
4. **Contract/domain tests** — fixtures schema validation, callback/status
   behavior, retry policy and explicit ACCEPT/REVIEW_REQUIRED/UNKNOWN outcomes.

Официальный NovaPay case — golden fixture. Mutation labels — это regression
cases, а не замена generated-code layers.

## Fact и inference

Безопасные факты: names/paths/methods/operationIds, explicit security scheme,
header names, request required list, exact enums, response codes, explicit
kopeck descriptions, `Retry-After`, текст про HMAC-SHA256 и schema `$ref`
targets.

Инференции, которые нельзя молча зашить:

- response `PayoutResponse.amount` имеет integer/example, но отдельное описание
  единиц не повторяет request description;
- `bank_code`/`card_number` conditionality живёт в description, а не в `oneOf`;
- отсутствие `required` у response не означает отсутствие operational invariant;
- HTTP `402`, `409`, `404` retryability и side effects нужно вывести в policy,
  а не объявлять из status code одного;
- `cancel` и `balance` — полезные дополнительные endpoints, но не должны
  маскироваться под обязательные методы BaseService;
- webhook path — обычный path, не OpenAPI callback и не top-level `webhooks`;
- `security: []` на webhook означает отсутствие OpenAPI auth requirement, но не
  отсутствие signature verification.

## Условие остановки

На этапе исходного research это считалось завершённым: выбран один доминирующий
вариант, собраны
37 mutation labels и агрегируемые metrics, определены safety gates, MVP order и
нерентабельные направления. Следующим шагом тогда была реализация после
отдельного решения команды; этот исторический пакет сам production
implementation не запускал.
