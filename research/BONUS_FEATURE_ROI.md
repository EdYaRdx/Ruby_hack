# ROI дополнительных features

Дата: 2026-09-03

Рейтинг рассчитан для solo implementation и judged demo. Features ценны только
после того, как core compiler сможет создать verified adapter.

| Feature | Value | Cost | Demo value | Risk | Priority | Decision |
|---|---|---:|---:|---|---:|---|
| Human Review Center | prevents unsafe guesses; exposes provenance and conflicts | 6–10 h | very high | can become a second product | P0/P1 | build file/CLI review manifest first; web view optional |
| Request/Response Preview | makes mappings and payload transforms legible | 3–5 h | high | preview may hide runtime differences | P1 | build deterministic dry-run from Blueprint |
| Integration Readiness | honest summary of blockers/review/warnings/coverage | 2–3 h | very high | fake percentage metrics | P1 | build counts and named checks, no synthetic confidence |
| Reusable Rules | improves second-provider speed without ML | 4–6 h | medium-high | unsafe global generalization | P1 | build scoped/versioned rules with explicit confirmation |
| Spec Drift | catches stale decisions after input changes | 1–2 h hash; 6–10 h semantic diff | high | noisy diffs | P0 hash / P2 diff | fingerprint now; semantic diff later |
| Generated RSpec | validates host contract and transformations | 4–6 h | high | tests can be shallow | P1 | generate focused contract and fixture specs |
| Regeneration Diff | makes reproducibility and review safer | 2–4 h | high | output noise if unstable | P1 | deterministic files + manifest diff |
| Web UI | polished review/demo surface | 12–24 h | high | consumes critical path; duplicate core | cut | defer until CLI/file workflow is proven |

## Рекомендуемый bonus bundle

Bundle с высоким ROI:

```text
review.yaml + readiness.md + request/response preview
      + input fingerprint + generated RSpec + deterministic diff
```

Он поддерживает product story `ANALYZE -> REVIEW -> FIX -> GENERATE -> VERIFY`,
не создавая второй semantic engine. Web UI явно является post-MVP projection
того же review manifest, а не отдельным source of truth.

## Критерии готовности bonus bundle

- каждый review item ссылается на evidence и source path;
- принятие decision меняет только resolved manifest/override, но не raw spec;
- preview генерируется из того же Blueprint, что Ruby и documentation;
- readiness перечисляет `blocking`, `review_required`, `warnings`, `unknowns` и
  preserved extra operations;
- повторный запуск с тем же fingerprint даёт стабильный diff;
- generated tests явно падают при изменении profile или fixture contract.
