# Ожидаемый score hackathon

## Основание оценки

`описание.docx` задаёт technical maximum 100 и industry maximum 20. Таблица
ниже намеренно conservative: предполагается polished MVP, но не поддержка всех
OpenAPI features и не идеальная live-provider integration.

## Техническое жюри: expected 95/100

| Criterion | Max | Expected | Confidence | What must exist | Main blocker |
|---|---:|---:|---|---|---|
| API specification parsing | 20 | 19 | high | all five operations, params/schemas, auth, statuses/errors, webhook and extra ops | unsupported OAS dialect/ref |
| Integration service generation | 25 | 24 | medium-high | BaseService class, request/status/error/callback methods, config and retry metadata | mismatch with host BaseService API |
| Data transformation correctness | 15 | 14 | medium | pointer mappings, explicit money conversion, exact statuses, conditionals | hidden provider semantics |
| Universality/adaptability | 10 | 9 | medium | no provider hardcode, extension registries, diagnostics for unsupported/ambiguous | broad unseen specs |
| Docs and test materials | 13 | 12 | high | INTEGRATION.md, fixtures.json, examples for requests/responses/webhooks | incomplete generated evidence |
| Use and demo | 10 | 9 | high | one CLI command, dry-run/inspect, readable diagnostics | demo environment failure |
| Technical quality | 10 | 8 | medium | separated layers, parser/codegen error handling, setup docs | solo time pressure |
| **Technical total** | **100** | **95** |  |  |  |

Обоснование subscores следует официальной разбивке: parsing получает полный score
за methods/parameters/auth/statuses, но один балл удержан за breadth; generation
теряет один балл за host-contract integration; transformation теряет один балл,
поскольку один universal case не доказывает undocumented provider semantics;
quality теряет два балла из-за риска unseen specifications.

## Отраслевое жюри: expected 18/20

| Criterion | Max | Expected | Confidence | Required evidence |
|---|---:|---:|---|---|
| Additional ideas | 6 | 5 | medium | Integration Readiness Report, evidence explanation, dry-run, mutation report |
| Presentation | 6 | 5 | medium | short story: manual 2–5 days -> inspect -> generate -> verify |
| Completeness | 8 | 8 | medium-high | generated service + docs + fixtures + CLI + diagnostics |
| **Industry total** | **20** | **18** |  |  |

## Итог и sensitivity

Conservative expected result: **113/120**. Разумный диапазон: 108–116.

| Failure mode | Approx. loss | Prevention |
|---|---:|---|
| generated class does not load against BaseService | -8 to -12 | contract fixture + `ruby -c` + generated smoke test |
| unsafe money/status/auth guess | -5 to -15 and trust loss | critical evidence gate; zero critical false accepts |
| webhook omitted or signature wrong | -3 to -7 | raw-body fixture and HMAC analyzer |
| only NovaPay hardcoded | -4 to -8 | mutations + second unseen fixture |
| unclear run/demo | -3 to -6 | one-command CLI, inspect report and friendly errors |

Score model — planning estimate, а не обещание. Benchmark определяет semantic
policy; реальный score по-прежнему зависит от judges и quality generated code.

## Приоритеты, ориентированные на score

Показатели ниже — acceptance checks, которые следует показать judges. Effort —
оценка P0 из `MVP_BACKLOG.md`; expected gain/hour — сигнал для приоритизации, а
не гарантированный линейный прирост score.

| Priority | Technical requirement | Measure | Responsible component | Effort | Loss risk | Expected gain/hour |
|---:|---|---|---|---:|---|---:|
| 1 | Generate a loading BaseService-compatible service | generated class/method contract, `ruby -c`, smoke fixtures | Blueprint + generator + verification | 5 h | very high | 4.8 |
| 2 | Parse operations, params, schemas, refs and auth | 5/5 reference operations and all critical refs discovered | parser adapter + Structural IR | 5 h | very high | 3.8 |
| 3 | Preserve critical transformations | explicit money, exact statuses, auth, idempotency and webhook tests | payment-aware analyzers + decision gate | 8 h | very high | 1.8 |
| 4 | Produce docs and fixtures | docs/fixtures generated from same Blueprint and schema-valid | projections + validator | 3 h + tests | high | 2.7 |
| 5 | Make the flow easy to demonstrate | one command, inspect output, readable error paths | OptionParser CLI + diagnostics | 3 h | medium-high | 3.0 |
| 6 | Prove universality | 37 mutations, second unseen fixture, no provider-specific branches | IR + alias registry + benchmark | 4 h | high | 2.3 |
| 7 | Make implementation resilient | four test layers, parser errors, deterministic regeneration | RSpec + CI gates | 4 h | medium | 2.0 |

Порядок первой implementation следует зависимостям (IR до generator), а таблица
объясняет, почему generated-contract и critical-meaning gates получают наибольшее
внимание в начале. Красивый UI не компенсирует отсутствующий service или
небезопасный amount/status mapping.
