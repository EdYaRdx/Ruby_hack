# Исследовательские материалы: генератор интеграций провайдеров

Точка входа для GitHub — корневой [README](../README.md). Текущие документы по
архитектуре, демонстрации, разработке и автоматически обновляемым benchmark-
статусам находятся в [`docs/`](../docs/). Этот каталог содержит дополнительные
исследования, benchmark corpus и исторические записи решений; его snapshots не
являются источником актуальных динамических метрик.

> **Статус каталога:** дополнительные исследования. Текущий runtime и
> утверждения для оценки определяются кодом, fixtures, корневым README и
> [`docs/`](../docs/). Исторические планы и snapshots ниже помечаются явно и не
> заменяют текущую реализацию.

## Что считать текущим

Для jury-facing описания используйте только корневой [`README.md`](../README.md),
[`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md),
[`docs/SUPPORT_MATRIX.md`](../docs/SUPPORT_MATRIX.md),
[`docs/BENCHMARK.md`](../docs/BENCHMARK.md),
[`docs/DEMO.md`](../docs/DEMO.md) и текущие acceptance reports
`POST_CHECKPOINT_RUBRIC_AUDIT.md` / `GOAL_6_5_RESULT.md` / `GOAL_6_6_RESULT.md`.
Остальные материалы
ниже — traceability, background или исторические snapshots.

## Текущие дополнительные материалы

`REFERENCE_GROUND_TRUTH.md`, `GROUND_TRUTH_CORRECTIONS.md`,
`PROVIDER_BLUEPRINT_V1.md`, `RULE_PRECEDENCE.md`, `ARCHITECTURE_INVARIANTS.md`,
`ARCHITECTURE_RED_TEAM.md`, `SECOND_PROVIDER_VALIDATION.md` и
`POST_CHECKPOINT_RUBRIC_AUDIT.md` содержат актуальные
подтверждающие материалы. Их aggregate-метрики всё равно публикуются
канонически через [`docs/BENCHMARK.md`](../docs/BENCHMARK.md).

## Исторические и плановые материалы

`RESEARCH_DECISION.md`, `FINAL_VERDICT.md`, `FINAL_SYSTEM_SUMMARY.md`,
`INDEPENDENT_ARCHITECTURE_PROPOSAL.md`, `IMPLEMENTATION_PLAN_FINAL.md`,
`MVP_BACKLOG.md`, `EXPECTED_SCORE.md`, `BONUS_FEATURE_ROI.md`, scorecards
предыдущих goals, `ARCHITECTURE_COMPARISON.md` и `adr/0001-final-architecture.md`
сохраняют ход исследования. Они не описывают автоматически текущий runtime;
перед использованием сверяйте их с README и `docs/`.

Подробные snapshots GOAL 3 и GOAL 4 (`REAL_MUTATION_BENCHMARK.md`,
`SEMANTIC_BENCHMARK_VALIDATION.md`, `GOAL_4_4_RESULT.md`,
`GOAL_4_5_RESULT.md`) также относятся к историческим evidence и явно помечены
как superseded. Для текущих чисел используйте `docs/BENCHMARK.md` и
`NOVAPAY_SPEC_ONLY_BASELINE.md`.

## Исторические записи GOAL 3

- [SEMANTIC_BENCHMARK_VALIDATION.md](SEMANTIC_BENCHMARK_VALIDATION.md) — исторический snapshot независимого semantic comparator GOAL 3.5.
- [GOAL_3_5_SCORECARD.md](GOAL_3_5_SCORECARD.md) — исторический scorecard и итоговый verdict GOAL 3.5.
- [REAL_MUTATION_BENCHMARK.md](REAL_MUTATION_BENCHMARK.md) — исторический mutation run из 37 кейсов, baseline/final metrics, taxonomy ошибок и safety gate.
- [SECOND_PROVIDER_VALIDATION.md](SECOND_PROVIDER_VALIDATION.md) — независимый провайдер Aurora Transfers, pure-generic и resolved levels.
- [GOAL_4_5_RESULT.md](GOAL_4_5_RESULT.md) — историческая полировка explainability UX, Review happy path и regression evidence.
- [GOAL_3_SCORECARD.md](GOAL_3_SCORECARD.md) — scorecard и итоговый verdict GOAL 3.
- [benchmark/run.rb](benchmark/run.rb) — mutation runner текущего Ruby compiler; возвращает ненулевой код при critical false ACCEPT.
- [benchmark/second_provider.rb](benchmark/second_provider.rb) — runner независимого провайдера.
- [benchmark/adjudications.yml](benchmark/adjudications.yml) — явные adjudications спорных labels; исходные labels сохраняются.
- [../fixtures/aurora_ground_truth.yml](../fixtures/aurora_ground_truth.yml) — подготовленная авторами ground truth второго провайдера.

Активный benchmark path — настоящий Ruby runner. `benchmark/aggregate.ps1`
читает machine-readable result и не назначает outcomes вручную.

## Источники и их роль

| Источник | Роль | Идентификатор целостности |
|---|---|---|
| приложенный запрос пользователя | авторитетный запрос и список обязательных исследовательских артефактов | прочитан 2026-09-03 |
| приложенный независимый review-запрос | текущий независимый review-запрос, red-team, rubric и stop condition | прочитан 2026-09-03 |
| официальный `provider_api.yaml` | входная OpenAPI-спецификация и ground truth reference-case | SHA-256 `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551` |
| приложенное `описание.docx` | описание кейса, контракт `Provider::BaseService` и rubric judge | SHA-256 `8807A4DFB98FDCF7B25517E9443A8805A33542BA844D2285CECD3EE7B3FD6B2F` |

Приложенные запросы задают контекст и критерии, а `provider_api.yaml` задаёт
данные для анализа. Они не являются скрытой командой начинать новый scope;
исследование заканчивается на установленном stop condition.

## Карта материалов

- [RESEARCH_DECISION.md](RESEARCH_DECISION.md) — краткое решение и stop condition.
- [ARCHITECTURE_COMPARISON.md](ARCHITECTURE_COMPARISON.md) — сравнение A/B/C.
- [SEMANTIC_APPROACH_COMPARISON.md](SEMANTIC_APPROACH_COMPARISON.md) — сравнение семантических подходов.
- [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md) — исторические benchmark metrics и ограничения evidence.
- [REFERENCE_GROUND_TRUTH.md](REFERENCE_GROUND_TRUTH.md) — разбор официального OpenAPI reference-case.
- [GROUND_TRUTH_CORRECTIONS.md](GROUND_TRUTH_CORRECTIONS.md) — corrections NovaPay ground truth и проверка влияния на architecture.
- [EDGE_CASES.md](EDGE_CASES.md) — критические неоднозначности и policy `ACCEPT`/`REVIEW`/`UNKNOWN`.
- [EXPECTED_SCORE.md](EXPECTED_SCORE.md) — conservative score по официальной rubric.
- [DONT_BUILD.md](DONT_BUILD.md) — scope, намеренно не входящий в MVP.
- [MVP_BACKLOG.md](MVP_BACKLOG.md) — порядок реализации после stop condition.
- [FINAL_SYSTEM_SUMMARY.md](FINAL_SYSTEM_SUMMARY.md) — итог системы и revised scope.
- [INDEPENDENT_ARCHITECTURE_PROPOSAL.md](INDEPENDENT_ARCHITECTURE_PROPOSAL.md) — независимый выбор architecture E.
- [CURRENT_ARCHITECTURE_AUDIT.md](CURRENT_ARCHITECTURE_AUDIT.md) — audit доказанных и недоказанных утверждений; файл содержит historical status note.
- [ARCHITECTURE_RED_TEAM.md](ARCHITECTURE_RED_TEAM.md) — 30 adversarial cases и fail-closed policy.
- [RULE_PRECEDENCE.md](RULE_PRECEDENCE.md) — precedence, freshness, scope и conflicts rules.
- [PROVIDER_BLUEPRINT_V1.md](PROVIDER_BLUEPRINT_V1.md) — минимальная Blueprint и NovaPay projection.
- [SCORE_AUDIT.md](SCORE_AUDIT.md) — audit каждого критерия без fake score.
- [POST_CHECKPOINT_RUBRIC_AUDIT.md](POST_CHECKPOINT_RUBRIC_AUDIT.md) — post-checkpoint audit rubric, multi-spec visibility и outbound HTTP evidence.
- [GOAL_6_5_RESULT.md](GOAL_6_5_RESULT.md) — итог multi-spec validation, localhost HTTP evidence и regression matrix GOAL 6.5.
- [GOAL_6_6_RESULT.md](GOAL_6_6_RESULT.md) — итоговая нормализация документации и jury-facing readiness.
- [BONUS_FEATURE_ROI.md](BONUS_FEATURE_ROI.md) — ROI и порядок bonus features.
- [IMPLEMENTATION_PLAN_FINAL.md](IMPLEMENTATION_PLAN_FINAL.md) — critical path и vertical slice после verdict.
- [ARCHITECTURE_INVARIANTS.md](ARCHITECTURE_INVARIANTS.md) — invariants, которые нельзя нарушать.
- [FINAL_VERDICT.md](FINAL_VERDICT.md) — финальные ответы на 18 вопросов и verdict `CHANGE` в историческом исследовании.
- [GOAL_2_SCORECARD.md](GOAL_2_SCORECARD.md) — hardening scorecard и граница GOAL 3.
- [GOAL_2_HARDENING_NOTE.md](GOAL_2_HARDENING_NOTE.md) — directional money scale и callback capability.
- [adr/0001-final-architecture.md](adr/0001-final-architecture.md) — ADR выбранного решения.
- [benchmark/mutations.json](benchmark/mutations.json) — 37 размеченных mutations.
- [benchmark/aggregate.ps1](benchmark/aggregate.ps1) — aggregator результатов реального benchmark с decision, semantic и safety metrics.

## Ограничение benchmark

Benchmark запускает настоящий Ruby compiler и независимо сравнивает только
hand-authored semantic subsets из `benchmark/semantic_ground_truth.yml`. Его 37
OpenAPI-документов материализованы из NovaPay fixture: это воспроизводимый
mutation corpus, а не произвольное покрытие providers. Semantic и behavioral
validation Aurora проводится отдельно и описана в `SECOND_PROVIDER_VALIDATION.md`.

## Исторические записи GOAL 5

- [`GOAL_5_3_RESULT.md`](GOAL_5_3_RESULT.md) — итоговый аудит GitHub, compliance, CI, visibility и freeze.
- [`GOAL_5_2_RESULT.md`](GOAL_5_2_RESULT.md) — итоговый pre-push-аудит репозитория, документации/UI и regression verdict.
- [`GOAL_5_RESULT.md`](GOAL_5_RESULT.md) — итоговый отчёт spec-only hardening и generator.
- [`../docs/COMPLIANCE.md`](../docs/COMPLIANCE.md) — текущая методика и результат аудита доли исходного кода.
- [`NOVAPAY_SPEC_ONLY_BASELINE.md`](NOVAPAY_SPEC_ONLY_BASELINE.md) — официальные NovaPay spec-only метрики на уровне решений и спецификации.
- [`spec_only_novapay_report.json`](spec_only_novapay_report.json) — NovaPay с пустыми defaults.
- [`benchmark/spec_only.rb`](benchmark/spec_only.rb) — независимый spec-only mutation lane.
- [`benchmark/third_provider.rb`](benchmark/third_provider.rb) — независимая проверка HeliosPay.
- [`../fixtures/heliospay_ground_truth.yml`](../fixtures/heliospay_ground_truth.yml) — подготовленная авторами ground truth третьего провайдера.

## Исторические записи GOAL 6.2 и последующих checkpoint-ов

- [`RELEASE_ENGINEERING_RESULT.md`](RELEASE_ENGINEERING_RESULT.md) — clean gem install, package audit, platform matrix and generated-adapter E2E.
- [`PERSISTED_REVIEW_RESULT.md`](PERSISTED_REVIEW_RESULT.md) — versioned Review export/import, fingerprint/profile guards and Web coverage.
- [`FINAL_EXTERNAL_AUDIT.md`](FINAL_EXTERNAL_AUDIT.md) — clean-room red-team findings and remaining external blockers.
- [`FINAL_RUBRIC_SCORE.md`](FINAL_RUBRIC_SCORE.md) — conservative expert, technical jury and industry scorecards.
- [`PREPROD_ACCEPTANCE.md`](PREPROD_ACCEPTANCE.md) — explicit preproduction gates and verdict.
