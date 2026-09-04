# Аудит score по официальной rubric

Дата: 2026-09-03

Это исторический audit того, что репозиторий мог продемонстрировать на этапе
2026-09-03. Это не присуждённый score. Research benchmark являлся policy
emulator; production Ruby implementation на момент этого audit в workspace ещё
не было. Актуальная реализация и результаты указаны в scorecards GOAL 3.5.

## Технические критерии (100 баллов)

| Criterion | Max | Owner in E | Current coverage | Remaining proof | Risk | Priority | Target |
|---|---:|---|---|---|---|---:|---:|
| API specification parsing | 20 | Ingest + Facts IR | research only: reference parsed manually | run parser against all 5 operations, refs, params, schemas, auth, errors, webhook, extra op | high | P0 | 19 |
| Integration service generation | 25 | Blueprint + Ruby projection | unimplemented; host contract absent | real `BaseServiceProfile`, loadable class, request/status/cancel/callback/error paths | very high | P0 | 24 |
| Data transformation correctness | 15 | Domain analyzers + gate | rules documented; no executable tests | money, nested fields, conditionals, exact statuses, idempotency and HMAC fixtures | very high | P0 | 14 |
| Universality/adaptability | 10 | Facts IR + extension registry | 37 mutation policies only; no real generated run | second unseen spec, provider-neutral rules, preserved unknown/extra endpoints | high | P0 | 9 |
| Docs and test materials | 13 | Projections + verification | research docs exist; generated artifacts absent | `INTEGRATION.md`, fixtures, request/response/webhook examples and validation | medium-high | P0 | 12 |
| Use and demo | 10 | CLI + diagnostics | flow specified, CLI absent | one-command analyze/review/generate/verify demo and readable diagnostics | medium | P1 | 9 |
| Technical quality | 10 | Layered package + CI gates | architecture documented; implementation unstarted | parser error handling, deterministic output, unit/contract tests, setup docs | high | P0 | 8 |
| **Technical total** | **100** |  | **0 awarded today** |  |  |  | **95 potential** |

## Отраслевые критерии (20 баллов)

| Criterion | Max | Responsible evidence | Current coverage | Gap | Priority | Target |
|---|---:|---|---|---|---:|---:|
| Additional ideas | 6 | Review Center, Readiness, Preview, drift, evidence ledger | concept/design only | implement at least Review Center + Readiness + dry-run | P1 | 5 |
| Presentation | 6 | CLI story and before/after artifacts | architecture narrative ready | live golden-provider demo with a visible review decision | P1 | 5 |
| Completeness | 8 | generated service + docs + fixtures + verification | no generated product artifacts | finish vertical slice and show all outputs | P0 | 8 |
| **Industry total** | **20** |  | **0 awarded today** |  |  | **18 potential** |

## Вывод audit

Предыдущие числа `95/100 + 18/20` — conservative potential score после
implementation, а не evidence того, что текущий repo получает 113/120. Главная
неопределённость — реальный host `BaseService` contract; вторая — semantic
quality вне NovaPay case. Нельзя заявлять score до того, как:

1. an actual parser consumes the supplied YAML;
2. a real (or explicitly supplied) profile validates the generated Ruby;
3. fixtures execute request, response, status, error and webhook paths;
4. mutated and unseen provider specs are run end-to-end;
5. all blocking decisions are visible and prevent generation.

## Аудит небезопасных shortcuts оценки

- Policy-emulator labels полезны для проверки decision policy, но не parser
  accuracy.
- Высокий evidence score не является probability correctness.
- Один `ruby -c` не доказывает host compatibility или money/status semantics.
- Равенство snapshots не доказывает provider correctness generated request.
- Чистая NovaPay demo не доказывает universality.
