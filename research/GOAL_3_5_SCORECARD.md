# GOAL 3.5: scorecard

> **Current GOAL 6.10 extension (2026-09-06):** the original GOAL 3.5 figures remain historical for the frozen mutation/Aurora scope. The additional independent corpus is `3/3` spec-only ACCEPT, `3/3` semantic, `3/3` generation/localhost transport and `3/3` behavioral vectors, with zero CaseDefaults and zero HUMAN_CONFIRMED overrides. Full details: [GOAL_6_10_RESULT.md](GOAL_6_10_RESULT.md).

> **ИСТОРИЧЕСКИЙ SNAPSHOT GOAL 3.5.** Это зафиксированный результат отдельного
> этапа. Текущие counts и aggregate metrics обновляются в
> [`docs/BENCHMARK.md`](../docs/BENCHMARK.md).

Дата: 2026-09-04

## Независимая semantic validation

| Metric | Result |
|---|---:|
| Mutation cases | 37 |
| Final semantic passes | 37/37 |
| Decision accuracy | 100.0% |
| Automatic ACCEPT rate | 48.6% |
| Safe decision coverage | 100.0% |
| REVIEW_REQUIRED rate | 40.5% |
| UNKNOWN rate | 10.8% |
| Semantic ACCEPT accuracy | 100.0% |
| Operation semantic accuracy | 100.0% |
| Money semantic accuracy | 100.0% |
| Status semantic accuracy | 100.0% |
| Auth semantic accuracy | 100.0% |
| Webhook semantic accuracy | 100.0% |
| Idempotency semantic accuracy | 100.0% |
| Field-mapping semantic accuracy | 100.0% |
| Critical false ACCEPTs | 0 |
| Generation success | 18/18 |
| Generated syntax | 100.0% |

## Независимое обнаружение ошибок

Comparator обнаружил одну реальную correctness issue: conflicting money-unit
evidence давала blocking REVIEW decision, но в Blueprint сохранялась resolved
conversion. Generic analyzer теперь удаляет такую conversion; regression test
защищает инвариант.

Assertion для M33 независимо подтверждает, что resolved local input refs входят
в `source.fingerprint_inputs`; одного root YAML hash недостаточно.

Две первые ошибки comparator-а были проблемами представления ground truth для
unresolved webhook algorithms; теперь `UNKNOWN` фиксируется явно.

Последующая provenance check также исправила hand-authored evidence subset M13:
после удаления amount descriptions источником не может быть `SPEC_DESCRIPTION`,
остаётся только `CASE_DEFAULT`.

## Aurora

| Level | Decision | Semantic comparison | Behavioral vectors |
|---|---|---|---|
| Pure generic | REVIEW_REQUIRED | PASS | not attempted |
| Generic + safe reusable rules | REVIEW_REQUIRED | PASS | not attempted |
| Minimal provider-specific resolution | ACCEPT | PASS | 4/4 PASS |

Resolved Aurora semantics независимо совпадают для operations, Bearer auth,
nested major-unit money, всех требуемых status mappings, webhook cryptography,
optional idempotency и preserved extras.

## Gates и architecture

- Full RSpec: 42 examples, 0 failures.
- NovaPay regression: PASS, official SHA unchanged, `ACCEPT`, zero REVIEW/BLOCKING.
- CLI verify и generated Ruby syntax: PASS.
- Architecture deviation: none. Comparator — benchmark/reporting layer; единственное compiler change — evidence-proven fail-closed money correction.

## Вердикт

BACKEND BENCHMARK VALIDATED

GO for GOAL 4 не выдаётся: Web UI намеренно остаётся вне scope GOAL 3.5 и не
реализован.
