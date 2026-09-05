# GOAL 3.5: независимая semantic benchmark validation

> HISTORICAL SNAPSHOT — this GOAL 3.5 checkpoint predates the current GOAL 5.1 metric terminology and regression baseline. Current judge-facing evidence is maintained in [docs/BENCHMARK.md](../docs/BENCHMARK.md), [GOAL_5_RESULT.md](GOAL_5_RESULT.md), [NOVAPAY_SPEC_ONLY_BASELINE.md](NOVAPAY_SPEC_ONLY_BASELINE.md), and [spec_only_novapay_report.json](spec_only_novapay_report.json).

Date: 2026-09-04

## Область проверки

Предыдущий benchmark в основном сравнивал `actual_decision` с expected
decision. GOAL 3.5 добавляет независимое сравнение вручную заданных semantic
subsets с полученным Blueprint, а также runtime checks для независимого Aurora
provider-а.

Текущий pipeline не изменён, кроме одной fail-closed correction, доказанной
comparator-ом: conflicting money-unit evidence больше не оставляет resolved
conversion candidate в Blueprint.

## Методика

```text
hand-authored mutation + semantic subset
  -> real Ruby compiler
  -> Blueprint
  -> independent semantic comparator
  -> generation/runtime verification
  -> final pass
```

Для ACCEPT cases:

```text
final_pass = decision_pass AND semantic_pass AND generation_runtime_pass
```

Для REVIEW_REQUIRED cases semantic safety дополнительно требует, чтобы expected
critical decision оставалась unresolved, и запрещает resolved unsafe value.
Generation не запускается. Для UNKNOWN cases unsupported item должен сохраняться
в `unknowns` или как compiler diagnostic; generation также не запускается.

Ground truth находится в `benchmark/semantic_ground_truth.yml`; он содержит
только relevant subsets, а не копии полных Blueprints.

## Определения metrics

| Metric | Formula |
|---|---|
| `decision_accuracy` | decision-pass cases / all cases |
| `automatic_accept_rate` | actual ACCEPT cases / all cases |
| `safe_decision_coverage` | final-pass cases / all cases |
| `review_required_rate` | actual REVIEW_REQUIRED cases / all cases |
| `unknown_rate` | actual UNKNOWN cases / all cases |
| `semantic_accept_accuracy` | expected ACCEPT cases with actual ACCEPT and semantic pass / expected ACCEPT cases |
| `*_semantic_accuracy` | passing relevant semantic subsets in the area / cases with that subset |
| critical false ACCEPT | critical case with unsafe ACCEPT decision or failed ACCEPT semantics |

Старое decision-only value сохраняется как
`legacy_decision_only_automatic_coverage`; it is not the final pass metric.

## Результаты 37 mutations

| Metric | Decision-only / old | Independent semantic validation |
|---|---:|---:|
| Cases | 37 | 37 |
| Passed | 37/37 | 37/37 |
| Decision accuracy | 100.0% | 100.0% |
| Automatic ACCEPT rate | not reported | 48.6% |
| Safe decision coverage | not reported | 100.0% |
| Legacy decision-only automatic coverage | 100.0% | 100.0% |
| Semantic ACCEPT accuracy | not reported | 100.0% |
| Operation semantic accuracy | not reported | 100.0% |
| Money semantic accuracy | not reported | 100.0% |
| Status semantic accuracy | not reported | 100.0% |
| Auth semantic accuracy | not reported | 100.0% |
| Webhook semantic accuracy | not reported | 100.0% |
| Idempotency semantic accuracy | not reported | 100.0% |
| Field-mapping semantic accuracy | not reported | 100.0% |
| REVIEW_REQUIRED rate | 40.5% | 40.5% |
| UNKNOWN rate | 10.8% | 10.8% |
| Critical false ACCEPTs | 0 | 0 |
| Generation success | 18/18 | 18/18 |
| Generated syntax | 100.0% | 100.0% |

Первый запуск comparator намеренно не скрывался: он провалил 3 cases. M12
выявил реальный conflict/conversion safety bug. M29 и M36 выявили mismatch в
ground-truth representation (`null` против явного `UNKNOWN` в Blueprint); это
исправлено в hand-authored expectation file.

Comparator также проверяет fingerprint subset для M33: resolved local
`components.yml` input должен присутствовать в `source.fingerprint_inputs` вместе
с resolved local-ref closure, а не только с root document hash.

После добавления provenance fields в independent money subset M13 сначала
провалился, потому что expectation всё ещё содержал удалённое
`SPEC_DESCRIPTION` evidence; hand-authored expectation исправлен на один
`CASE_DEFAULT`. Compiler из-за этого finding не менялся.

## Self-tests comparator

RSpec покрывает пять независимых checks:

- корректный ACCEPT + неверная operation → FAIL;
- корректный ACCEPT + неверный money factor → FAIL;
- корректный REVIEW + скрытый resolved critical mapping → FAIL;
- корректный UNKNOWN + потерянный unsupported item → FAIL;
- корректная decision + корректная semantics + runtime → PASS.

## Aurora: semantic и behavioral validation

Второй provider проверен на трёх уровнях resolution. Pure generic и safe
reusable rules остаются `REVIEW_REQUIRED` с одним blocking issue. Resolved level
— `ACCEPT`; semantic comparator принимает operations, money, auth, statuses,
webhook, idempotency, field mappings и preserved extra operations. Четыре
independent behavioral vectors проходят: host create request, provider status
response, settled webhook и declined webhook.

Machine-readable outputs:

- `tmp/benchmark/results.json`;
- `tmp/benchmark/second_provider.json`.

## Regression gate

- official NovaPay SHA-256: `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551`;
- Blueprint: `ACCEPT`, `0 REVIEW`, `0 BLOCKING`;
- `1500.50 ↔ 150050`: exact;
- webhook invalid signature: fail-closed;
- default CLI generate/verify: PASS;
- full RSpec at the current documentation checkpoint: `59 examples, 0 failures`.

## Вердикт

GOAL 3.5 завершён для проверенного mutation corpus и reference provider Aurora.
Это подтверждает independent semantic correctness для declared subsets, но не
является утверждением о production readiness для произвольных provider-ов.
