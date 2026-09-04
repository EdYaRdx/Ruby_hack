# Итоговый implementation plan

Дата: 2026-09-03

Это исторический build plan после изменения architecture. На момент составления
production implementation ещё не была начата; на машине также не было usable
Ruby runtime, поэтому runtime gate являлся явной dependency. Актуальные
результаты реализации находятся в scorecards GOAL 3/3.5.

## Critical path

```text
real host contract/profile
  -> parser + resolver + input fingerprint
  -> facts IR + diagnostics
  -> analyzers + precedence/decision gate
  -> resolved Blueprint + review manifest
  -> deterministic Ruby/docs/fixtures projections
  -> ruby -c + contract tests + fixture tests
  -> real mutate -> generate -> execute -> compare benchmark
```

Profile и executable Ruby environment — gates, а не optional polish.

## Первый build slice

Сначала реализовать только один provider-shaped vertical slice:

1. разобрать OpenAPI 3.0.3 YAML с local refs и сохранить source locations;
2. выдать facts для пяти NovaPay endpoints, schemas, security, statuses,
   errors, idempotency и webhook;
3. загрузить explicit `BaseServiceProfile`/test stub;
4. разрешить create/status/callback, amount, status, API key, idempotency и
   webhook signature через case-scoped evidence; сохранить cancel как extra,
   если выбранный profile явно не объявляет cancel binding;
5. записать Blueprint и review manifest;
6. сгенерировать один Ruby service, `INTEGRATION.md`, fixtures и focused RSpec;
7. запустить `ruby -c`, загрузить class против profile stub и выполнить fixtures.

Exit criterion: reviewer может проверить одно decision, изменить scoped override,
перегенерировать output и увидеть детерминированный verification result.

## План первого дня

| Stage | Output | Gate |
|---|---|---|
| 0–1 h | repo setup, runtime check, host profile fixture | stop if contract cannot be represented |
| 1–3 h | parser adapter, resolver, fingerprint and source locations | invalid/ref fixtures produce diagnostics |
| 3–5 h | Facts IR + endpoint/field/schema inventory | 5/5 reference endpoints preserved |
| 5–8 h | operation/auth/money/status/idempotency/webhook analyzers | candidates carry evidence/provenance |
| 8–10 h | precedence + review manifest + Blueprint validator | critical unknowns block generation |
| 10–13 h | Ruby/docs/fixtures generator | output has no semantic branching |
| 13–16 h | contract and fixture verification | generated code loads and paths execute |
| 16–18 h | CLI inspect/generate/verify + readiness | one-command demo is repeatable |

Если runtime или BaseService contract недоступны, безопасный day-one exit — demo
parser + review manifest; generated compatibility нельзя имитировать.

## Поэтапная поставка

### P0 — correctness core

- parser, refs, fingerprint и facts IR;
- BaseServiceProfile и test-only stub;
- analyzers для operation, fields, money, statuses, auth, idempotency,
  webhook и conditionals;
- precedence, stale detection и Blueprint validator;
- deterministic generator с одним canonical provider slice;
- `ruby -c`, contract fixtures и blocking diagnostics.

### P1 — полнота, видимая judge

- `OptionParser` CLI: `analyze`, `inspect`, `generate`, `verify`;
- Review Center как YAML/Markdown manifest и CLI confirmation;
- Readiness report и request/response preview;
- generated RSpec, docs и fixtures;
- second unseen provider fixture и real mutation harness.

### P2 — bounded extensions

- semantic spec diff;
- дополнительные OpenAPI dialects и external-ref policies;
- provider rule packs с signed/versioned review history;
- Web UI как projection над тем же manifest.

## Что сокращать в первую очередь

При нехватке времени сокращайте scope в таком порядке: Web UI, semantic spec
diff, broad OAuth2 flows, generic plugin DSL, fuzzy ranking, multi-language
output, затем broad OpenAPI coverage. Нельзя сокращать profile boundary,
critical abstention, сохранение extra operations, generated fixtures или
verification gates.

## Предотвращение поздних ошибок

- Проверяйте host method names и argument shapes до написания templates.
- Проверяйте raw-body webhook verification до добавления удобной parsed-payload
  abstraction.
- Проверяйте major/minor/decimal money variants до claims о generic mapping.
- Запускайте changed-spec fixture, чтобы доказать, что stale overrides блокируют
  regeneration.
- Сравнивайте фактическое behavior generated Ruby, а не только Blueprint snapshots.
