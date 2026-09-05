# Исследовательские материалы: генератор интеграций провайдеров

Точка входа для GitHub — корневой [README](../README.md). Текущие документы по
архитектуре, демонстрации, разработке и автоматически обновляемым benchmark
статусам находятся в [`docs/`](../docs/). Этот каталог содержит supporting
research, benchmark corpus и исторические записи решений; его snapshots не
являются источником актуальных dynamic metrics.

> **Статус каталога:** supporting research. Текущий runtime и judge-facing
> claims определяются кодом, fixtures, корневым README и [`docs/`](../docs/).
> Исторические планы и snapshots ниже помечаются явно и не заменяют текущую
> реализацию.

## Текущие supporting materials

`REFERENCE_GROUND_TRUTH.md`, `GROUND_TRUTH_CORRECTIONS.md`,
`PROVIDER_BLUEPRINT_V1.md`, `RULE_PRECEDENCE.md`, `ARCHITECTURE_INVARIANTS.md`,
`ARCHITECTURE_RED_TEAM.md`, `REAL_MUTATION_BENCHMARK.md`,
`SEMANTIC_BENCHMARK_VALIDATION.md`, `SECOND_PROVIDER_VALIDATION.md` и
`GOAL_4_4_RESULT.md`, `GOAL_4_5_RESULT.md` содержат
актуальные technical evidence. Их aggregate-метрики всё равно публикуются
канонически через [`docs/BENCHMARK.md`](../docs/BENCHMARK.md).

## Исторические и плановые материалы

`RESEARCH_DECISION.md`, `FINAL_VERDICT.md`, `FINAL_SYSTEM_SUMMARY.md`,
`INDEPENDENT_ARCHITECTURE_PROPOSAL.md`, `IMPLEMENTATION_PLAN_FINAL.md`,
`MVP_BACKLOG.md`, `EXPECTED_SCORE.md`, `BONUS_FEATURE_ROI.md`, scorecards
предыдущих goals, `ARCHITECTURE_COMPARISON.md` и `adr/0001-final-architecture.md`
сохраняют ход исследования.
Они не описывают автоматически текущий runtime; перед использованием сверяйте
их с README и `docs/`.

## GOAL 3: артефакты реальной проверки

- [SEMANTIC_BENCHMARK_VALIDATION.md](SEMANTIC_BENCHMARK_VALIDATION.md) — независимый semantic comparator, safety rules и metrics GOAL 3.5.
- [GOAL_3_5_SCORECARD.md](GOAL_3_5_SCORECARD.md) — scorecard и итоговый verdict GOAL 3.5.
- [REAL_MUTATION_BENCHMARK.md](REAL_MUTATION_BENCHMARK.md) — реальный mutation run из 37 кейсов, baseline/final metrics, taxonomy ошибок и safety gate.
- [SECOND_PROVIDER_VALIDATION.md](SECOND_PROVIDER_VALIDATION.md) — независимый провайдер Aurora Transfers, pure-generic и resolved levels.
- [GOAL_4_5_RESULT.md](GOAL_4_5_RESULT.md) — explainability UX polish, Review happy path и regression evidence.
- [GOAL_3_SCORECARD.md](GOAL_3_SCORECARD.md) — scorecard и итоговый verdict GOAL 3.
- [benchmark/run.rb](benchmark/run.rb) — mutation runner текущего Ruby compiler; возвращает ненулевой код при critical false ACCEPT.
- [benchmark/second_provider.rb](benchmark/second_provider.rb) — runner независимого провайдера.
- [benchmark/adjudications.yml](benchmark/adjudications.yml) — явные adjudications спорных labels; исходные labels сохраняются.
- [../fixtures/aurora_ground_truth.yml](../fixtures/aurora_ground_truth.yml) — hand-authored ground truth второго провайдера.

Активный benchmark path — настоящий Ruby runner. `benchmark/aggregate.ps1`
читает machine-readable result и не назначает outcomes вручную.

## Источники и их роль

| Источник | Роль | Идентификатор целостности |
|---|---|---|
| attached user request | авторитетный запрос пользователя и список обязательных исследовательских артефактов | прочитан 2026-09-03 |
| attached independent review request | текущий независимый review-запрос, red-team, rubric и stop condition | прочитан 2026-09-03 |
| официальный `provider_api.yaml` | входная OpenAPI-спецификация и ground truth reference-case | SHA-256 `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551` |
| attached `описание.docx` | описание кейса, контракт `Provider::BaseService` и rubric judge | SHA-256 `8807A4DFB98FDCF7B25517E9443A8805A33542BA844D2285CECD3EE7B3FD6B2F` |

Приложенные запросы задают context и критерии, а `provider_api.yaml` задаёт
данные для анализа. Они не являются скрытой командой начинать новый scope;
исследование заканчивается на установленном stop condition.

## Карта материалов

- [RESEARCH_DECISION.md](RESEARCH_DECISION.md) — краткое решение и stop condition.
- [ARCHITECTURE_COMPARISON.md](ARCHITECTURE_COMPARISON.md) — сравнение A/B/C.
- [SEMANTIC_APPROACH_COMPARISON.md](SEMANTIC_APPROACH_COMPARISON.md) — сравнение semantic approaches.
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
hand-authored semantic subsets из
`benchmark/semantic_ground_truth.yml`. Его 37 OpenAPI documents materialized из
NovaPay fixture: это воспроизводимый mutation corpus, а не произвольное
покрытие providers. Semantic и behavioral validation Aurora проводится отдельно
и описана в `SECOND_PROVIDER_VALIDATION.md`.
## Goal 5 evidence

- [`GOAL_5_RESULT.md`](GOAL_5_RESULT.md) — final spec-only hardening and generator report.
- [`spec_only_novapay_report.json`](spec_only_novapay_report.json) — NovaPay with empty defaults.
- [`benchmark/spec_only.rb`](benchmark/spec_only.rb) — independent spec-only mutation lane.
- [`benchmark/third_provider.rb`](benchmark/third_provider.rb) — blind HeliosPay validation.
- [`../fixtures/heliospay_ground_truth.yml`](../fixtures/heliospay_ground_truth.yml) — hand-authored third-provider ground truth.
