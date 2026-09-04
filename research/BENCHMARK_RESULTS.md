# Результаты mutation benchmark

> Исторический policy-emulator artifact. Актуальные generated results находятся в
> [`docs/BENCHMARK.md`](../docs/BENCHMARK.md). Полное evidence GOAL 3 находится в
> [REAL_MUTATION_BENCHMARK.md](REAL_MUTATION_BENCHMARK.md); этот файл сохранён
> для research history; этот файл не является источником текущего статуса.

## Протокол

- Source: официальная fixture `provider_api.yaml`, SHA-256
  `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551`.
- Baseline: OpenAPI 3.0.3, 5 path/method operations, 17 schemas/refs или
  response components, значимых для generator.
- Dataset: 37 одиночных mutations, включая все обязательные изменения из user
  request. Expected labels ниже были назначены до сравнения policies.
- Runner: `benchmark/aggregate.ps1` читает JSON labels и агрегирует явные outcome
  profiles. Сетевой доступ и скрытые provider data не используются.
- Scope: decision-policy benchmark. Он проверяет, принимает ли approach,
  отправляет ли на review или блокирует известную mutation; это не production
  OpenAPI parser.

## Baseline facts, использованные в labels

| Concern | Ground truth |
|---|---|
| Operations | `POST /payouts`, `GET /payouts/{payout_id}`, `POST /payouts/{payout_id}/cancel`, `POST /webhooks/payout`, `GET /balance` |
| Auth | `ApiKeyAuth`, API key in header `X-API-Key`; webhook has `security: []` |
| Create request | required `amount`, `currency`, `external_id`, `recipient`; JSON body; optional `Idempotency-Key` UUID header |
| Money | provider `request.amount` is integer minor RUB/kopecks; minimum `100000`; canonical Space Payments `operation.amount` is major RUB and request conversion is `×100`; response conversion is `/100` |
| Conditional fields | `bank_code` required for `recipient.type=sbp`; `card_number` required for `type=card`, both stated in descriptions only |
| Status | `pending`, `processing`, `completed`, `failed`, `cancelled` |
| Errors | 400, 401, 402, 409, 422, 429, 500 on create; 404 on status; 409 on cancel |
| Retry | only 429 explicitly has `Retry-After` integer seconds |
| Idempotency policy | OpenAPI `Idempotency-Key` is optional; an adapter choice to always send it is `ADAPTER_POLICY`, not `SPEC_FACT` |
| Webhook | ordinary POST path, `X-NovaPay-Signature`, explicit HMAC-SHA256 description, raw body needed for safe verification |
| Extra operations | cancel and balance have no direct BaseService method by default; preserve them as extra operations; `/balance` is non-blocking unless a profile binds it canonically |

## Ожидаемый результат каждой mutation

`expected_decision` — безопасный automation outcome. `expected_operation` —
canonical candidate или diagnostic bucket. Review является успешным safety
result, а не ошибкой parser.

| ID | Mutation | Expected decision | Expected candidate / behavior |
|---|---|---|---|
| M01 | `/payouts` -> `/transfers` | REVIEW_REQUIRED | candidate create_payout; transfer semantics may change retry behavior |
| M02 | `/payouts` -> `/withdrawals` | REVIEW_REQUIRED | candidate create_payout; withdrawal lifecycle needs review |
| M03 | `createPayout` -> `initiateTransfer` | REVIEW_REQUIRED | candidate create_payout; name is not proof |
| M04 | `createPayout` -> `makeWithdrawal` | REVIEW_REQUIRED | candidate create_payout; name is not proof |
| M05 | remove `operationId` | ACCEPT | infer from path/method/schema/text |
| M06 | change tags | ACCEPT | ignore advisory tag change when stronger evidence agrees |
| M07 | change summary | ACCEPT | summary is supporting evidence only |
| M08 | `amount` -> `sum` | REVIEW_REQUIRED | candidate amount, no auto mapping of money-critical field |
| M09 | `amount` -> `total` | REVIEW_REQUIRED | candidate amount, aggregate-vs-charge ambiguity |
| M10 | nested `money.value` | REVIEW_REQUIRED | candidate amount, unit/ownership not explicit |
| M11 | amount explicitly minor units | ACCEPT | preserve integer minor-unit representation |
| M12 | amount explicitly major units | ACCEPT | deterministic x100 conversion when rule is explicit |
| M13 | remove amount unit description | REVIEW_REQUIRED | leave conversion unknown; no guessing |
| M14 | `completed` -> `settled` | REVIEW_REQUIRED | terminal synonym requires evidence |
| M15 | `completed` -> `success` | REVIEW_REQUIRED | success is semantically ambiguous |
| M16 | `failed` -> `declined` | REVIEW_REQUIRED | candidate rejected, not automatic final mapping |
| M17 | `cancelled` -> `voided` | REVIEW_REQUIRED | candidate rejected, side effect requires review |
| M18 | add unknown terminal status | UNKNOWN | block final-status mapping |
| M19 | API key header -> Bearer | ACCEPT | explicit supported Bearer scheme |
| M20 | API key header -> query API key | ACCEPT | explicit supported scheme plus URL leakage warning |
| M21 | `X-API-Key` -> `X-Client-Token` | ACCEPT | use declared header name |
| M22 | rename `Idempotency-Key` | ACCEPT | update name while semantic description remains |
| M23 | remove idempotency | REVIEW_REQUIRED | disable automatic retry/reuse |
| M24 | webhook path -> `/callbacks/payment` | ACCEPT | preserve body/signature policy |
| M25 | webhook path -> `/notifications/payout` | ACCEPT | preserve body/signature policy |
| M26 | webhook as OpenAPI callback | ACCEPT | normalize callback into webhook IR |
| M27 | webhook as OAS 3.1 top-level webhook | ACCEPT | normalize top-level webhook into IR |
| M28 | remove webhook | ACCEPT | polling-only output plus warning |
| M29 | remove HMAC algorithm | REVIEW_REQUIRED | signature header alone is insufficient |
| M30 | add extra `/limits` | ACCEPT | preserve as `EXTRA_UNMAPPED` |
| M31 | add `/balance` when it already exists | UNKNOWN | duplicate path/method conflict |
| M32 | cancel -> void | REVIEW_REQUIRED | action synonym may change side effects |
| M33 | resolvable local external `$ref` | ACCEPT | resolve in allowlisted root, keep provenance |
| M34 | unresolved `$ref` | UNKNOWN | stop codegen with exact pointer |
| M35 | ambiguous `POST /transactions` | UNKNOWN | no reliable payout mapping |
| M36 | remove descriptions | REVIEW_REQUIRED | structure remains, semantics weakened |
| M37 | remove examples | ACCEPT | schema/description evidence remains; warn about lower evidence |

## Итоговый aggregate output

Запускать из корня репозитория:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\benchmark\aggregate.ps1
```

Наблюдавшийся output (37 cases):

| Policy | ACCEPT | Precision | Safe coverage | Review | Unknown | Critical false accepts |
|---|---:|---:|---:|---:|---:|---:|
| Exact deterministic rules | 7 | 100.0% | 32.4% | 5 | 25 | 0 |
| Domain dictionaries + rules | 19 | 78.9% | 73.0% | 12 | 6 | 4 |
| Rules + lexical aliases | 24 | 62.5% | 59.5% | 10 | 3 | 9 |
| Rules + fuzzy lexical similarity | 29 | 58.6% | 56.8% | 4 | 4 | 12 |
| Rules + schema/structure | 23 | 73.9% | 64.9% | 8 | 6 | 6 |
| Hybrid without abstention | 32 | 53.1% | 45.9% | 0 | 5 | 15 |
| **Hybrid + abstention** | **17** | **100.0%** | **89.2%** | **16** | **4** | **0** |

`Mutation pass rate` — точное совпадение decision, включая корректно
заблокированные `UNKNOWN`; `safe coverage` не включает корректно заблокированные
unknown. Policy emulator сообщает следующие pass rates semantic sub-suites.
Знаменатели не включают кейсы, для которых expected result этой area — `UNKNOWN`.

| Policy | Operation mapping | Field/money mapping | Status mapping | Auth | Idempotency | Webhook |
|---|---:|---:|---:|---:|---:|---:|
| Exact deterministic rules | 33.3% | 62.5% | 20.0% | 0.0% | 50.0% | 33.3% |
| Domain dictionaries + rules | 88.9% | 100.0% | 40.0% | 100.0% | 100.0% | 66.7% |
| Rules + lexical aliases | 55.6% | 75.0% | 40.0% | 100.0% | 100.0% | 66.7% |
| Rules + fuzzy lexical similarity | 66.7% | 50.0% | 0.0% | 100.0% | 100.0% | 100.0% |
| Rules + schema/structure | 55.6% | 62.5% | 60.0% | 100.0% | 100.0% | 100.0% |
| Hybrid without abstention | 55.6% | 37.5% | 0.0% | 100.0% | 50.0% | 83.3% |
| **Hybrid + abstention** | **100.0%** | **100.0%** | **100.0%** | **100.0%** | **100.0%** | **100.0%** |

| Policy | Mutation pass rate | Ruby generation pass rate |
|---|---:|---:|
| Exact deterministic rules | 43.2% | не измерялось: в baseline отсутствовал Ruby runtime |
| Domain dictionaries + rules | 83.8% | не измерялось: в baseline отсутствовал Ruby runtime |
| Rules + lexical aliases | 62.2% | не измерялось: в baseline отсутствовал Ruby runtime |
| Rules + fuzzy lexical similarity | 56.8% | не измерялось: в baseline отсутствовал Ruby runtime |
| Rules + schema/structure | 73.0% | не измерялось: в baseline отсутствовал Ruby runtime |
| Hybrid without abstention | 56.8% | не измерялось: в baseline отсутствовал Ruby runtime |
| **Hybrid + abstention** | **100.0%** | **не измерялось: в baseline отсутствовал Ruby runtime** |

Выбранная policy достигает на этом dataset целевого safety invariant: zero
critical false accepts для money units, idempotency, retry safety, webhook
signature, final status и auth assumptions. Корректный возврат `UNKNOWN`
безопасен, но не засчитывается в safe coverage.

## Gate Ruby generation

`ruby -c` и generated service smoke tests намеренно **не измерялись в
историческом окружении baseline**, потому что тогда Ruby не был установлен в
workspace. Обязательный implementation gate:

```text
each ACCEPTed blueprint -> generate -> ruby -c service.rb
                         -> fixtures/schema validation
                         -> BaseService contract smoke test
```

Цель исследования — 100% syntax pass для accepted cases. Последующий benchmark
run должен добавлять фактическую колонку `ruby_generation_pass_rate`; этот
исторический документ не превращает отсутствие runtime в fabricated result.

## Ограничения и следующий эксперимент

Profile outcomes — это явные decision policies, а не competing full parsers. Их
достаточно, чтобы выбрать abstention и определить safety boundaries, но
недостаточно для claims о generalization на arbitrary providers. До production
implementation следует перенести labels в Ruby specs и добавить минимум две
unseen provider-like fixtures. Zero-critical-false-accept gate должен остаться
инвариантом.
