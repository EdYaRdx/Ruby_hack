# MVP backlog после stop condition исследования

> **ИСТОРИЧЕСКИЙ ПЛАН.** Этот backlog сохраняет порядок первоначальной работы и
> не является списком незавершённых требований текущего checkout. Фактическое
> состояние описано в корневом README и [`docs/`](../docs/).

Список упорядочен по ожидаемому приросту score на час работы одного человека.
Это только backlog; данная research-задача не запускает перечисленные items.

## P0 — gates до demo

| Order | Work | Acceptance evidence | Estimate |
|---:|---|---|---:|
| 1 | Freeze Blueprint schema and decision vocabulary | versioned schema + sample NovaPay blueprint | 2 h |
| 2 | Build parser adapter and Structural IR | all five operations, refs, params, schemas and responses discovered | 5 h |
| 3 | Implement critical analyzers | money/auth/status/idempotency/webhook/error/conditional unit tests | 8 h |
| 4 | Implement evidence ledger and gate | all 37 mutations produce expected decision class; zero critical false accepts | 4 h |
| 5 | Generate BaseService-compatible Ruby | class/method contract, deterministic output, `ruby -c` | 5 h |
| 6 | Generate docs and fixtures from same Blueprint | no duplicated semantic logic; examples match schemas | 3 h |
| 7 | Add RSpec golden + contract layers | official NovaPay fixture green; generated code smoke test green | 4 h |
| 8 | Add one-command CLI and diagnostics | `integrate --spec ... --provider ... --out ...` works, readable errors | 3 h |

Оценка P0: 34 person-hours без учёта настройки окружения и неизвестной
интеграции с host framework.

## P1 — high-value bonus

1. `inspect`/dry-run report с endpoints, decisions, evidence и warnings.
2. Integration Readiness Report с явными missing/unknown fields.
3. Mutation benchmark command и компактное summary результатов.
4. Regeneration diff mode для показа deterministic output.

Целевой bonus budget: 4–6 h; остановиться после первых двух items, если
presentation уже достаточно ясна.

## P2 — только после всех gates

- generated RSpec skeleton для accepted operations;
- second unseen provider-like fixture;
- bounded alias registry configuration;
- optional Thor CLI, только если CLI вырастет за пределы одной command.

## Критерии готовности

- OpenAPI parsing errors stop before codegen.
- Каждое generated semantic decision указывает на evidence.
- `ACCEPT` precision >=99% на mutation set.
- Critical false accepts = 0 для money units, idempotency, retry safety, webhook
  signature, final statuses и auth assumptions.
- Safe decision coverage >=85%.
- Ruby syntax и generated contract tests pass.
- `service.rb`, `INTEGRATION.md`, `fixtures.json` — projections одного и того же
  Blueprint.
