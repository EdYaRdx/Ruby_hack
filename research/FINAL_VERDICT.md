# Итоговый вердикт

Дата: 2026-09-03

> Исторический research snapshot до реализации vertical slice. Актуальные
> результаты реализации и benchmark указаны в `GOAL_3_5_SCORECARD.md`,
> `REAL_MUTATION_BENCHMARK.md` и `SECOND_PROVIDER_VALIDATION.md`.

## 1. Какую бизнес-проблему мы решаем?

Сокращаем ручную работу по созданию Ruby-интеграции платёжного провайдера:
из OpenAPI и проверяемых дополнительных правил строим адаптер,
совместимый с небольшим canonical contract Space Payments, с документацией,
fixtures и проверками. Продукт не «понимает любой API без человека», а
безопасно компилирует известные семантические паттерны и останавливается на
критических неизвестных.

## 2. Как должен выглядеть конечный продукт?

Одна core-система и CLI:

```text
provider spec + optional scoped rules
  -> ANALYZE: facts, candidates, evidence, readiness
  -> REVIEW: manifest with confirm/remap/unresolved
  -> FIX: fresh scoped override
  -> GENERATE: Ruby adapter + INTEGRATION.md + fixtures + RSpec
  -> VERIFY: syntax, profile contract, requests, responses, statuses, webhook
```

Выходом также являются `Blueprint`, decision log, request/response preview,
readiness report и deterministic regeneration diff. Web UI, если появится,
должен только отображать этот же manifest.

## 3. Если не учитывать текущую архитектуру, какую архитектуру я выбрал бы?

Вариант E: **profiled evidence-gated integration compiler** — ingest и
fingerprint, facts-only IR, независимые analyzers, evidence/decision layer,
human review, validated Blueprint, deterministic projections и verification.
Это минимальная архитектура, в которой unknown/conflict — нормальные значения,
а не исключение из шаблона.

## 4. Совпадает ли она с нашей?

С ядром — да: `IR -> analyzers -> evidence -> Blueprint -> generator`.
С текущим scope — нет. Предложенная архитектура должна быть изменена четырьмя
точками ниже, поэтому итоговый verdict — `CHANGE`.

## 5. Что в нашей архитектуре действительно сильное?

- разделение structural IR и semantic analyzers;
- evidence/provenance и review-first вместо безусловной генерации;
- отдельные анализаторы для money, status, auth, idempotency, webhook и
  conditionals;
- Blueprint как граница между reasoning и templates;
- сохранение extra operations и unknowns;
- единый core для CLI и будущего UI;
- детерминированные Ruby/docs/fixtures из одного решения;
- явная проверка сырых webhook bytes и критический abstention.

## 6. Что лишнее?

До MVP лишние: Web UI, широкий plugin DSL, fuzzy semantic matching, multi-
language codegen, полноценный OAuth2 matrix, semantic spec diff и попытка
поддержать весь OpenAPI. Они увеличивают поверхность, но не доказывают
совместимость с `BaseService` и корректность денег/status/webhook.

## 7. Что отсутствует?

Отсутствуют executable parser/generator, реальный host contract, профиль
`BaseService`, review persistence, stale fingerprint enforcement, Blueprint
validator, generated contract tests, runtime fixture tests и end-to-end
benchmark. Также отсутствует доказательство, что текущие thresholds не только
policy-emulator rules.

## 8. Что нужно изменить до implementation?

1. Зафиксировать `BaseServiceProfile` и test-only stub с точными method
   signatures.
2. Разделить immutable Facts IR, candidate/review manifest и resolved
   Blueprint.
3. Ввести source fingerprint, scoped/versioned overrides и `STALE_OVERRIDE`
   blocker.
4. Утвердить precedence из `RULE_PRECEDENCE.md`.
5. Утвердить fail-closed gate для money, status, auth, webhook, logical
   `request_method` и conditionals.
6. Зафиксировать Blueprint v1 и валидатор до написания ERB.
7. Определить real Ruby/runtime test gate и только затем строить vertical
   slice.

## 9. Какой Provider Blueprint v1 использовать?

`research/PROVIDER_BLUEPRINT_V1.md`: schema v1 с source fingerprint,
BaseServiceProfile, endpoints/operations, field mappings, money, statuses,
errors, idempotency, webhook, conditionals, extra operations, decisions,
warnings и unknowns. Generator читает только validated resolved Blueprint.

## 10. Как должен работать Human Review?

Система показывает каждое `ACCEPT`, `REVIEW_REQUIRED`, `UNKNOWN` и `BLOCKING`:
кандидат, результат, evidence locations/excerpts, conflicts, provenance,
scope/fingerprint и объяснение. Человек выбирает `confirm`, `remap`,
`supply_override` или `exclude`. Критические decisions нельзя закрыть
простым «continue»; после изменения создаётся свежий manifest, validator
пересчитывает readiness, затем разрешается generation.

## 11. Нужна ли reusable Rule Knowledge Base в scope хакатона?

Да, но только узкая P1-версия: versioned rules с явным scope и ручным
подтверждением. Она ускоряет второй provider и не требует ML. Автоматически
глобализовать high-risk правило нельзя; provider override остаётся локальным.

## 12. Нужен ли Spec Drift в scope?

Да, P0 в минимальной форме: hash/fingerprint входа и блок stale overrides.
Полный semantic diff — P2. Даже простой fingerprint предотвращает тихую
регенерацию по устаревшему решению.

## 13. Нужен ли Web UI?

Нет в MVP. File/CLI Review Center даёт нужную безопасность и демонстрацию за
долю стоимости. UI можно добавить позже как read/write projection над тем же
manifest, без отдельной логики маппинга.

## 14. Какой минимальный MVP?

OpenAPI 3.0.3 input, local `$ref`, один `BaseServiceProfile`, NovaPay golden
slice, facts IR, пять canonical/extra endpoint decisions, operation/field/
money/status/auth/idempotency/webhook/conditional analyzers, precedence gate,
Blueprint validator, file review, deterministic Ruby adapter, docs, fixtures,
RSpec и CLI `analyze/inspect/generate/verify`.

## 15. Какой critical path?

```text
BaseServiceProfile
 -> parser/ref resolver/fingerprint
 -> facts IR
 -> analyzers + evidence
 -> precedence + review manifest
 -> Blueprint validator
 -> deterministic projections
 -> ruby -c + host contract + fixture execution
 -> real mutation/unseen-provider benchmark
```

## 16. Какие features вырезать?

Сразу вырезать из critical path Web UI, multi-language output, broad OAuth,
plugin DSL, fuzzy matching, generic auto-learning, semantic drift diff и
поддержку незнакомых OpenAPI dialects. Если времени меньше, вырезать сначала
UI и polish, но не verification, provenance, profile boundary или critical
abstention.

## 17. Какие реальные риски дисквалификации / потери баллов?

- заявить универсальность по одному NovaPay YAML;
- приписать Q&A defaults самому OpenAPI;
- сгенерировать неработающий класс из-за неизвестного BaseService;
- ошибиться в money units, status terminality или raw-body HMAC;
- потерять `/balance` как extra operation;
- принять heuristic как факт;
- показать policy-emulator metrics как качество реального алгоритма;
- не иметь повторяемого demo, fixtures и проверки regeneration;
- сделать UI, но не иметь исполняемого vertical slice.

## 18. Архитектура: FREEZE, CHANGE или REJECT AND REPLACE?

# CHANGE

Точное изменение: сохранить существующее ядро, но заменить неявные границы
следующими явными границами:

```text
OpenAPI/Q&A/overrides
  -> Ingest + resolver + fingerprint
  -> immutable Facts IR
  -> independent analyzers
  -> evidence ledger + precedence engine
  -> Candidate/Review Manifest
  -> Human confirmation + scoped fresh overrides
  -> resolved Provider Blueprint v1
  -> Blueprint validator / readiness gate
  -> deterministic Ruby + docs + fixtures + RSpec + preview
  -> executable verification against BaseServiceProfile
```

Это не `REJECT AND REPLACE`: сильное ядро сохраняется. Но это и не `FREEZE`:
без профиля host contract, stale enforcement и реального executable benchmark
архитектура пока обещает больше, чем доказано.

## Порядок implementation после verdict

1. Получить/зафиксировать host profile и установить Ruby test runtime.
2. Реализовать parser/ref resolver/fingerprint и Facts IR.
3. Реализовать analyzers и precedence, затем 30 red-team fixtures.
4. Реализовать review manifest и Blueprint validator.
5. Реализовать генерацию одного verified NovaPay slice.
6. Добавить docs, fixtures, RSpec, CLI, readiness и preview.
7. Запустить реальные mutations и второй unseen provider; только после этого
   делать claims о качестве и решать, нужен ли UI.

Этот review не запускал production implementation. После этого verdict
исследовательская stop condition считалась выполненной; implementation была
следующей отдельной authorized phase.
