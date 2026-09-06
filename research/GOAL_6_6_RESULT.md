# GOAL 6.6 — итог нормализации документации

Дата проверки: 2026-09-06

## Граница работы

Задача выполнена как documentation-only hardening. Новые features, product
semantics, analyzer behavior, Provider Blueprint, generator, runtime adapter,
benchmarks и tests не изменялись. Изменения ограничены актуализацией текстов,
ссылок, описаний доказательств и generated judge-facing status blocks.

## Инвентаризация документации

| Область | Роль | Действие |
|---|---|---|
| `README.md` | GitHub и jury-facing entrypoint | Структура перестроена вокруг ценности, pipeline, запуска, доказательств и ограничений; stale wording исправлен. |
| `docs/ARCHITECTURE.md` | Текущая архитектура | Описаны pipeline, Facts IR, Evidence, Manifest, Blueprint, Generator, Verification, Persisted Review и runtime boundary; исторические GOAL headings удалены. |
| `docs/BENCHMARK.md` | Текущие benchmark metrics | Формулы и decision/semantic/safety terminology оставлены в generated актуальном виде. |
| `docs/SUPPORT_MATRIX.md` | Текущая матрица поддержки | Ссылка и граница заявлений проверены; матрица не обещает универсальность. |
| `docs/DEMO.md` | 4-минутный сценарий | Добавлены checkpoints, 20-секундное объяснение и CLI fallback. |
| `docs/DEVELOPMENT.md`, `docs/DOCS_POLICY.md`, `docs/GLOSSARY.md`, `docs/COMPLIANCE.md` | Инженерная и терминологическая опора | Исправлены CI/runtime формулировки и согласованы термины. |
| `research/README.md` и текущие acceptance reports | Traceability и evidence | Явно разделены текущие документы и исторические snapshots; добавлен этот отчёт. |
| `examples/novapay/` | Канонический generated example | Пути и список артефактов описываются без устаревшего hardcoded count. |
| `THIRD_PARTY.md`, `provider_compiler.gemspec`, `.github/workflows/ci.yml` | Зависимости, package и CI | Проверены ссылки и граница внешнего runtime; CI wording отражает Windows/Linux и Ruby 3.3/4.0. |

## README и jury-facing guide

- Elevator pitch, problem statement и отличие от обычного OpenAPI generator
  находятся в начале README.
- Pipeline объясняет путь `OpenAPI → Facts IR → Evidence/Review → Blueprint →
  Ruby adapter → Verification`.
- Quick start проверен командами `bundle install`, `rspec`, `inspect`, `analyze`,
  `generate`, `verify`; Web entrypoint дополнительно проверен через `GET /health`.
- Разделы `Что проверено` и `Что не заявляется` явно ограничивают claims.
- Validation matrix различает NovaPay reference case, Aurora и HeliosPay
  synthetic fixtures и Frozen black-box cases; 37 и 12 обозначены как cases,
  а не как количество реальных providers.

## Текущая архитектура и explainability

`docs/ARCHITECTURE.md` описывает текущие слои без истории GOAL:

- Facts отвечают на вопрос «что присутствует во входе»;
- Review Manifest отвечает «почему предложено/принято решение»;
- Resolved Provider Blueprint отвечает «что будет сгенерировано»;
- generated Ruby отвечает «как это исполняется».

Зафиксированы `FACT != INFERENCE`, provenance, fail-closed behavior, Persisted
Review с fingerprint stale rejection, `EXTRA_OPERATION`, а также отдельная
граница между локальным HTTP transport verification и неисполненным внешним
provider sandbox.

## Consistency audit

- Устаревшие формулировки исправлены: 4 категории (CI matrix, persisted Review
  labels, artifact count и compliance percentages).
- Broken relative Markdown links: `0`.
- Absolute Windows paths в текущих документах: `0`.
- Stale mixed-language UI labels/placeholders и запрещённые inference-service
  claims в judge-facing документах: `0`.
- Исторические neural/LLM идеи остаются только в явно помеченных historical /
  not-current материалах и не описывают текущий runtime.
- `update_docs` выполнен дважды; второй запуск не изменил snapshot.
- `update_examples` выполнен дважды; второй запуск не изменил generated example.

## Evidence и regression

| Проверка | Результат |
|---|---:|
| Полный RSpec | `111 examples, 0 failures, 1 expected Windows pending` |
| NovaPay CLI regression | `ACCEPT`, `14 accepted`, `0 REVIEW_REQUIRED`, `0 BLOCKING`, `generation_ready=true` |
| Reference mutation benchmark | `37/37` cases; decision `100.0%`; semantic ACCEPT `100.0%`; critical false ACCEPT `0`; generation `18/18` |
| Mutation semantic areas | operation / money / status / auth / webhook / idempotency / field mapping: `100.0%` каждая |
| Mutation decision metrics | automatic ACCEPT `48.6%`; safe decision coverage `100.0%`; review `40.5%`; unknown `10.8%` |
| Aurora independent lane | `3/3` levels; resolved `ACCEPT`; behavioral vectors `4/4` |
| HeliosPay independent lane | `2/2` levels; resolved behavioral vectors `4/4` |
| Frozen black-box corpus | `12/12`; safe semantic accuracy `100.0%`; false ACCEPT `0`; unsafe generation `0`; crashes `0` |
| Local outbound HTTP E2E | `PASS`; внешний provider sandbox не вызывался |
| Ruby share audit | production `90.6%`; production + tests `93.1%` |
| `git diff --check` | `PASS` |

Legacy `automatic_coverage` не используется как judge-facing automatic ACCEPT
rate; он сохранён только для исторического сравнения machine results.

## CI и freeze

CI запускается после публикации этого checkout и должен подтвердить четыре
комбинации: Windows/Linux × Ruby 3.3/4.0. Идентификатор run и ссылки на jobs
будут добавлены в этот отчёт после push; это не изменяет продуктовую семантику.

## Финальный статус

- DOCUMENTATION READY FOR JURY: `YES`
- PRODUCT SEMANTICS CHANGED: `NO`
- PROJECT CLEAN BEFORE COMMIT: `YES`
- READY TO FREEZE AFTER CI: `YES`
