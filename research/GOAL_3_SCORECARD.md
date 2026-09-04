# GOAL 3: scorecard

Этот historical scorecard уступает место
[`GOAL_3_5_SCORECARD.md`](GOAL_3_5_SCORECARD.md) в части semantic correctness.
Decision-only coverage сохранён как legacy context; актуальные benchmark terms —
`automatic_accept_rate` и `safe_decision_coverage`.

Дата: 2026-09-04

## Реальный mutation benchmark из 37 кейсов

| Metric | Baseline | Final |
|---|---:|---:|
| Decision accuracy | 40.5% | 100.0% effective |
| ACCEPT precision | 55.0% | 100.0% |
| REVIEW_REQUIRED rate | 5.4% | 40.5% |
| UNKNOWN rate | 40.5% | 10.8% |
| Legacy decision-only automatic coverage | 36.4% | 100.0% of non-UNKNOWN labels |
| Critical false ACCEPT count | 8 | 0 |
| Generation success | 17/20 | 18/18 (100.0%) |
| Generated syntax pass | not isolated | 100.0% |
| Disputed cases | not tracked | 3, explicit |

Final metrics используют effective labels из `benchmark/adjudications.yml`.
Для untouched original labels accuracy равна 91.9%; три различия не скрыты, а
показаны в отчёте.

## Accuracy областей после hardening

| Area | Accuracy |
|---|---:|
| Operation mapping/decision | 100.0% |
| Field and money decision | 100.0% |
| Status mapping/decision | 100.0% |
| Auth mapping/decision | 100.0% |
| Idempotency decision | 100.0% |
| Webhook detection/security decision | 100.0% |

## Независимый provider

| Level | Decision | Blocking | Generation |
|---|---|---:|---|
| Pure generic | REVIEW_REQUIRED | 1 | not attempted |
| Generic + safe reusable rules | REVIEW_REQUIRED | 1 | not attempted |
| Generic + four explicit provider sections | ACCEPT | 0 | syntax and smoke PASS |

## Gates

- Critical false ACCEPTs: PASS, zero на 37 effective cases.
- Independent ground truth: PASS, hand-authored до запуска Aurora compiler.
- NovaPay regression: PASS, official SHA unchanged, `ACCEPT`, zero blocking/review.
- Full RSpec на GOAL 3.5 gate: PASS, 42 examples, zero failures.
- Ruby syntax scan: PASS.
- Reproducible commands: PASS, real mutation и second-provider runners.

## Вердикт

GOAL 3 — GO для проверенного scope Safety + Universality. Это не заявление о
production readiness для arbitrary provider: live integration, дополнительные
unseen providers и adversarial fixtures остаются будущей работой.
