# Проверка универсальности и безопасности

Текущая validation состоит из трёх независимых gates:

1. regression suite на RSpec;
2. mutation benchmark из 37 self-authored adversarial кейсов на основе NovaPay,
   где hand-authored semantic
   subsets сравниваются с фактической Blueprint;
3. semantic comparison второго провайдера Aurora и hand-authored behavioral
   vectors.

Официальный `provider_api.yaml` NovaPay — reference input организатора. Сам
mutation benchmark — воспроизводимый self-authored corpus, а не набор тестов,
предоставленный организатором, и не заявление, что 37 mutations представляют
всех провайдеров. Его ground truth находится в
[`research/benchmark/semantic_ground_truth.yml`](../research/benchmark/semantic_ground_truth.yml).
Aurora — независимый synthetic second provider; его ground truth и behavioral
vectors находятся в [`fixtures/`](../fixtures/). Comparator проверяет не только
совпадение decision и отсутствие crash, но и независимые semantic subsets,
fail-closed safety и generation/runtime gates.

## Определения метрик

Для `N` benchmark cases:

- `decision_accuracy` = число кейсов, где actual decision совпадает с effective
  adjudicated decision / `N`;
- `safe_decision_coverage` = число кейсов, прошедших decision, independent
  semantics, safety и применимые generation/runtime gates / `N`;
- `automatic_coverage` (legacy) = число кейсов, прошедших только старый
  decision-only gate / `N`; это историческое сравнение, не показатель safety;
- `decision_automation_rate` = accepted decisions / total decisions. The old
  case-level `automatic_accept_rate` field remains in machine output only for
  historical comparison and must not be used as a readiness claim;
- `review_required_rate` = actual `REVIEW_REQUIRED` cases / `N`;
- `unknown_rate` = actual `UNKNOWN` cases / `N`;
- `semantic_accept_accuracy` = expected `ACCEPT` cases с независимо совпавшей
  Blueprint / expected `ACCEPT` cases;
- accuracy каждой semantic area = совпавшие hand-authored subsets / число
  кейсов, где эта area объявлена релевантной;
- В aggregate эти области публикуются как `operation_semantic_accuracy`,
  `money_semantic_accuracy`, `status_semantic_accuracy`,
  `auth_semantic_accuracy`, `webhook_semantic_accuracy`,
  `idempotency_semantic_accuracy` и `field_mapping_semantic_accuracy`.
- `critical_false_accept_count` = critical cases, принятые с неверной или
  небезопасной semantic result;
- generation success считается только для кейсов, где generation запускалась.

Старое decision-only automatic-coverage сохраняется в machine result только для
исторического сравнения. Поле `automatic_accept_rate` не является judge-facing
automation или safety metric.

## Актуальный автоматически сгенерированный результат

`bin/update_docs` запускает реальные benchmark scripts и RSpec, читает их JSON
results и заменяет только отмеченный ниже блок. Источники —
`tmp/benchmark/results.json`, `tmp/benchmark/second_provider.json` и JSON-отчёт
RSpec. Это воспроизводимые ignored artifacts, а не вручную отредактированные
утверждения.

<!-- BEGIN GENERATED: BENCHMARK -->
**Reference mutation benchmark**

- Scope: 37 adversarial mutations of one reference provider domain, not 37 providers.
- Independent decision/semantic cases passed: 37/37.
- Decision accuracy: 100.0%; semantic ACCEPT accuracy: 100.0%.
- Semantic areas (operation / money / status / auth / webhook / idempotency / field mapping): 100.0% / 100.0% / 100.0% / 100.0% / 100.0% / 100.0% / 100.0%.
- Critical false ACCEPTs: 0; generation: 18/18 attempts passed.

**Spec-only lanes**

- NovaPay official baseline: decision automation 10/14 (71.4%); review rate 4/14 (28.6%); blocking entries 3; fully auto-ready 0/1 (0.0%); false ACCEPTs 0; unsafe generation attempts 0.
- NovaPay mutation lane: 7 cases, 98 decisions; decision automation 74/98 (75.5%); review rate 24/98 (24.5%); blocking entries 17; fully auto-ready 0/7 (0.0%); false ACCEPTs 0; unsafe generation attempts 0.
- Aurora: spec-only decision automation 12/14 (85.7%), fully auto-ready 0/1 (0.0%); resolved fully auto-ready 1/1 (100.0%); behavioral vectors 4/4.
- HeliosPay: spec-only decision automation 11/13 (84.6%), fully auto-ready 0/1 (0.0%); resolved fully auto-ready 1/1 (100.0%); behavioral vectors 4/4.

Legacy `automatic_coverage` remains in machine results for historical comparison only. It is not a judge-facing automation or safety metric.
<!-- END GENERATED: BENCHMARK -->

## Decision-level vs spec-level metrics

The judge-facing metrics use separate denominators:

- `decision_automation_rate` = accepted decisions / total decisions.
- `review_rate` = `REVIEW_REQUIRED` decisions / total decisions.
- `fully_auto_ready_rate` = specifications with zero `REVIEW_REQUIRED` decisions
  and zero blocking entries / total specifications.
- `blocking_entries` is reported separately because one decision can produce
  multiple blocking entries.
- `critical_false_accepts` counts unsafe ACCEPTs for hand-authored critical
  cases.
- `unsafe_generation_attempts` counts generation attempts while a critical
  decision is unresolved; it is zero only when the runner proves no such
  attempt occurred.

Decision automation is not full-spec readiness. A spec-only lane can have
accepted decisions while still being unable to generate safely.

## Интерпретация

Высокий accept rate сам по себе недостаточен. Полезность системы определяется
тем, совпадают ли accepted Blueprint с независимой семантикой и не превращается
ли нерешённая critical information в скрытое generated value. Поэтому benchmark
раздельно показывает correctness, safety и generation.
The 37-case NovaPay reference benchmark and the spec-only lane are separate
measurements. The spec-only lane runs with empty provider defaults and reports
decision automation, review rate, blocking entries, full-spec auto-ready rate,
and safety metrics. It must not be merged into a single universal-accuracy
number.

The independent third-provider lane is HeliosPay. Its hand-authored ground
truth is stored before the run and includes 202 success handling, nested money,
query auth, extra operations, runtime errors, and webhook vectors.
