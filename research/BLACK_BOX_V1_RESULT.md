# Frozen black-box v1 — final result

После targeted runtime/OpenAPI hardening текущая реализация повторно прогнана
на том же frozen corpus. Input specs, ground truth и SHA-256 manifest не
переписывались.

## Final metrics

| Metric | Baseline | Final |
|---|---:|---:|
| Cases passed by independent semantic comparator | 7/12 | 12/12 |
| Safe semantic accuracy | 58.3% | 100.0% |
| Decision automation rate | 0.0% | 0.0% |
| REVIEW_REQUIRED rate | 33.3% | 66.7% |
| UNKNOWN rate | 66.7% | 33.3% |
| Fully auto-ready rate | 0.0% | 0.0% |
| Critical false ACCEPTs | 0 | 0 |
| Unsafe generation attempts | 0 | 0 |
| Compiler crashes | 0 | 0 |

Рост REVIEW_REQUIRED и снижение UNKNOWN — это исправление качества evidence,
а не попытка увеличить ACCEPT. Frozen corpus не содержит fully resolved
production-ready case, поэтому generation/runtime rate для этой lane равен
`0/0`; реальные generated HTTP vectors вынесены в отдельный runtime test.

## Resolved failures

- StatusMapper теперь учитывает schemas из operation request/response и
  resolved local `$ref` closure.
- Required custom query/header/cookie parameters сохраняются в
  `unsupported_features`; required values без host/config source имеют
  `generation_impact: BLOCKING`.
- Unsupported auth/media/callback features получают machine-readable
  diagnostics.
- Structural `method + path + schema` fallback без `operationId` сохранён:
  это существующий безопасный контракт, подтверждённый regression M05; он не
  превращён в искусственный blocker.

## Corpus integrity

- Frozen commit: `7257a89`.
- Root/local input hashes: `black_box_v1/MANIFEST.json`.
- Ground truth hash не менялся после freeze.
- Final `failures.json` пуст.

Машинные результаты: [`black_box_v1/results.json`](black_box_v1/results.json) и
[`black_box_v1/failures.json`](black_box_v1/failures.json).

