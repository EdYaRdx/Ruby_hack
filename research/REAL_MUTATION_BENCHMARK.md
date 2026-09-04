# GOAL 3: реальный mutation benchmark

Date: 2026-09-04

## Методика

Benchmark запускает production Ruby pipeline. Поток выглядит так:

```text
hand-authored mutation case
  -> materialized OpenAPI document
  -> OpenAPI loader, local ref resolver and immutable Facts IR
  -> real analyzers and evidence decisions
  -> Review Manifest and Blueprint
  -> deterministic generation and generated Ruby verification
  -> independent semantic subset/safety comparison
```

Исходные labels находятся в `benchmark/mutations.json`. Они не вычисляются из
вывода analyzer-ов. Изначально в репозитории были labels/descriptions, а не 37
полных YAML-файлов; `benchmark/run.rb` materializes каждую описанную mutation из
независимого NovaPay fixture. Это ограничение явно зафиксировано, а
materialized documents сохраняются в `tmp/benchmark/runs/`.

Semantic expectations заданы вручную в
`benchmark/semantic_ground_truth.yml`. Теперь case считается пройденным только
если совпадают decision, релевантная семантика Blueprint, safety state и
generated runtime verification. Legacy decision-only result сохраняется как
отдельная metric и не является условием успешного прохождения benchmark.

Run:

```powershell
bundle exec ruby research/benchmark/run.rb
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\benchmark\aggregate.ps1
```

Команда записывает `tmp/benchmark/results.json` и завершается с ненулевым кодом,
если обнаружен critical false ACCEPT.

## Baseline до hardening

Baseline был запущен до изменений analyzer-ов и сохранён в
`tmp/benchmark/baseline.json`.

| Metric | Baseline |
|---|---:|
| Cases | 37 |
| Exact decision matches | 15 / 37 (40.5%) |
| ACCEPT count | 20 |
| ACCEPT precision | 55.0% |
| REVIEW_REQUIRED | 2 (5.4%) |
| UNKNOWN | 15 (40.5%) |
| Legacy decision-only automatic coverage | 36.4% |
| Critical false ACCEPTs | 8 |
| Generated smoke passes | 17 / 20 accepted blueprints |

Восемь critical false ACCEPT cases: M01, M02, M03, M08, M09, M10, M13 и M23.
Дополнительно обнаружен один non-critical false ACCEPT — M35.

## Итоговый запуск после semantic validation

Effective labels включают только три явно документированные adjudications из
`benchmark/adjudications.yml`; исходные labels в dataset не изменены.

| Metric | Final |
|---|---:|
| Cases | 37 |
| Decision accuracy (decision-only) | 37 / 37 (100.0%) |
| Safe decision coverage (decision + semantics + runtime) | 37 / 37 (100.0%) |
| Original-label accuracy | 91.9% |
| ACCEPT count | 18 |
| Automatic ACCEPT rate | 48.6% (18 / 37) |
| ACCEPT precision | 100.0% |
| REVIEW_REQUIRED | 15 (40.5%) |
| UNKNOWN | 4 (10.8%) |
| Legacy decision-only automatic coverage | 100.0% |
| Semantic ACCEPT accuracy | 100.0% |
| Operation semantic accuracy | 100.0% |
| Money semantic accuracy | 100.0% |
| Status semantic accuracy | 100.0% |
| Auth semantic accuracy | 100.0% |
| Webhook semantic accuracy | 100.0% |
| Idempotency semantic accuracy | 100.0% |
| Field-mapping semantic accuracy | 100.0% |
| Critical false ACCEPTs | 0 |
| Generation success | 18 / 18 (100.0%) |
| Generated Ruby syntax pass | 100.0% |
| Disputed/adjudicated cases | 3: M12, M13, M32 |

Точность decision по областям и всех независимо проверенных semantic areas
составляет 100.0% по effective labels. Это не утверждение о корректности
непредставленной семантики: comparator проверяет только вручную заданные
релевантные subsets.

## Таксономия сбоев и исправления

### Идентификация operation

Baseline слишком сильно доверял create-like operationId. Generic mapper теперь
агрегирует operationId, path domain, method, request shape и response shape.
Конфликтующие domains дают review; generic endpoint `/transactions` остаётся
UNKNOWN; structurally clear create endpoint без operationId может быть принят.
Непривязанные cancel/void-like endpoints сохраняются как extras и не
исполняются как canonical action.

### Поля и деньги

Defaults больше не скрывают отсутствующее поле provider-а. Direct aliases,
вложенный `money.value`, destination-like recipient fields и response paths
сверяются с resolved schema. Money conversion остаётся направленной и
использует BigDecimal; decimal values в одинаковых units допустимы, а
major-to-minor output должен быть exact integer.

Первый semantic-validation run выявил реальный fail-closed defect в M12 conflict
case: decision была blocking REVIEW_REQUIRED, но в Blueprint оставалась resolved
identity conversion. Generic money analyzer теперь очищает обе directional
conversions при конфликте evidence о provider unit; поведение покрыто regression
test.

Последующая независимая provenance assertion выявила ground-truth error в M13:
после удаления amount descriptions provider money evidence должна быть только
`CASE_DEFAULT`, а не `SPEC_DESCRIPTION`. Ожидание исправлено; compiler из-за
этого finding не менялся.

### Status и webhook

Известные, но не подтверждённые status synonyms становятся REVIEW_REQUIRED с
кандидатом `BUILTIN_RULE`; действительно неизвестные terminal values остаются
UNKNOWN. Webhook discovery поддерживает обычные notification paths, callbacks и
top-level webhooks OpenAPI 3.1. Отсутствие cryptographic/raw-body semantics
блокирует generation. Provider без webhook представляется как polling-only и
по-прежнему может безопасно генерироваться.

### Idempotency и projection

Отсутствующий idempotency parameter даёт REVIEW_REQUIRED и не означает retry
safety. Optional headers остаются отделёнными от requiredness в `SPEC_FACT`.
Generated request/response projection теперь следует Blueprint field mappings,
включая nested provider paths, вместо предположения о flat NovaPay body.

## Спорные cases

Исходные labels сохранены. Следующие cases исключены из обсуждения «ни один
case» только через явный adjudication file и учитываются в отчёте:

| Case | Original | Effective | Reason |
|---|---|---|---|
| M12 | ACCEPT | REVIEW_REQUIRED | explicit major-unit spec text conflicts with active minor-unit case defaults |
| M13 | REVIEW_REQUIRED | ACCEPT | active named-case defaults explicitly supply minor units and scale 100 |
| M32 | REVIEW_REQUIRED | ACCEPT | profile does not bind cancel; void is preserved as a non-blocking extra |

Это споры о ground truth/input contract, а не скрытые green cases.

## Вывод по safety

Реализация достигла zero critical false ACCEPTs и 37/37 полных
semantic-validation passes на текущем corpus. Это evidence в пользу frozen
safety policy, но не доказательство общего покрытия provider-ов. Независимый
semantic and behavioral result для Aurora описан в
`SECOND_PROVIDER_VALIDATION.md`.
