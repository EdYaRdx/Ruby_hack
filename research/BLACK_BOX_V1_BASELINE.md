# Frozen black-box v1 — baseline

Baseline снят на неизменённом compiler после локального freeze commit
`7257a89` (`test: freeze black-box provider corpus v1`). Corpus содержит 12
independent synthetic provider configurations, все используют
`profiles/space_payments_v1.yml`. `specs/**` и `ground_truth.yml` после freeze
не изменялись; advisory errata находится в `research/black_box_v1/ERRATA.md`.

## Baseline metrics

| Metric | Result |
|---|---:|
| Cases | 12 |
| Safe semantic accuracy | 58.3% (7/12) |
| Decision automation rate | 0.0% |
| REVIEW_REQUIRED rate | 33.3% |
| UNKNOWN rate | 66.7% |
| Fully auto-ready rate | 0.0% |
| Generation success rate | 0/0 attempted |
| Runtime vector rate | 0/0 |
| Critical false ACCEPTs | 0 |
| Unsafe generation attempts | 0 |
| Compiler crashes | 0 |

Формулы:

- `safe_semantic_accuracy = independently passed cases / total cases`;
- `decision_automation_rate = ACCEPT decisions / total cases`;
- `review_rate = REVIEW_REQUIRED cases / total cases`;
- `unknown_rate = UNKNOWN cases / total cases`;
- `fully_auto_ready_rate = ACCEPT + verified generation cases / total cases`;
- `generation_success_rate = passed generation attempts / generation attempts`;
- `runtime_vector_rate = passed runtime vectors / executed runtime vectors`.

Нулевой automation rate ожидаем для этого frozen corpus: cases намеренно
содержат unresolved status/auth/money/transport features и проверяют безопасное
воздержание, а не максимизацию ACCEPT.

## Baseline failures

| Case | Baseline result | Classification | Root cause |
|---|---|---|---|
| `02_query_202` | `UNKNOWN` вместо hand-authored `REVIEW_REQUIRED` | IMPLEMENTATION_BUG | status enums находились в operation response, но StatusMapper сканировал только components |
| `03_bearer_polling` | `UNKNOWN` вместо `REVIEW_REQUIRED` | IMPLEMENTATION_BUG | та же потеря inline status evidence |
| `05_missing_operation_id` | `UNKNOWN` вместо `REVIEW_REQUIRED` | conservative over-abstention | structural operation fallback не отдавал отдельную advisory evidence; unsafe ACCEPT не возник |
| `09_required_parameters` | decision совпал, но semantic subset не прошёл | IMPLEMENTATION_BUG | required custom query/header values не сохранялись как diagnostics и могли быть молча потеряны |
| `12_local_refs` | `UNKNOWN` вместо `REVIEW_REQUIRED` | IMPLEMENTATION_BUG | status evidence из resolved external schema не доходила до StatusMapper |

Все baseline failures были fail-closed: `critical_false_accept_count = 0`,
`unsafe_generation_attempt_count = 0`, `compiler_crash_count = 0`.

Полный машинный результат: [`black_box_v1/baseline_results.json`](black_box_v1/baseline_results.json).

