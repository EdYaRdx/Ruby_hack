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
- `automatic_accept_rate` = actual `ACCEPT` cases / `N`;
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

Старое decision-only automatic-coverage сохраняется в machine result для
исторического сравнения. Оно не является safety metric и не должно называться
`automatic_accept_rate`.

## Актуальный автоматически сгенерированный результат

`bin/update_docs` запускает реальные benchmark scripts и RSpec, читает их JSON
results и заменяет только отмеченный ниже блок. Источники —
`tmp/benchmark/results.json`, `tmp/benchmark/second_provider.json` и JSON-отчёт
RSpec. Это воспроизводимые ignored artifacts, а не вручную отредактированные
утверждения.

<!-- BEGIN GENERATED: BENCHMARK -->
**Mutation benchmark NovaPay**

- Кейсы: пройдено 37/37.
- decision_accuracy: 100.0%.
- automatic_accept_rate: 48.6%.
- safe_decision_coverage: 100.0%.
- review_required_rate: 40.5%; unknown_rate: 10.8%.
- semantic_accept_accuracy: 100.0%.
- Operations / money / statuses / auth / webhook / idempotency / field mappings: 100.0% / 100.0% / 100.0% / 100.0% / 100.0% / 100.0% / 100.0%.
- critical_false_accept_count: 0.
- NovaPay spec-only lane: 7/7; automatic_accept_rate: 0.0%; safe_decision_coverage: 100.0%; critical false ACCEPTs: 0.
- HeliosPay: levels 2/2; resolved behavioral vectors 4/4; critical false ACCEPTs: 0.
- Generation: успешно 18/18 попыток; generated Ruby syntax pass rate: 100.0%.
- Второй provider Aurora: semantic levels 3/3, behavioral vectors 4/4; semantic accuracy: 100.0%; critical false ACCEPTs: 0.

Legacy `automatic_coverage`: 100.0%. Значение оставлено для сравнения и не используется как safety gate.
<!-- END GENERATED: BENCHMARK -->

## Интерпретация

Высокий accept rate сам по себе недостаточен. Полезность системы определяется
тем, совпадают ли accepted Blueprint с независимой семантикой и не превращается
ли нерешённая critical information в скрытое generated value. Поэтому benchmark
раздельно показывает correctness, safety и generation.
The 37-case NovaPay reference benchmark and the spec-only lane are separate
measurements. The spec-only lane runs with empty provider defaults and reports
`automatic_accept_rate`, `safe_decision_coverage`, `review_required_rate`,
`unknown_rate`, `decision_accuracy`, and critical false ACCEPTs. It must not be
merged into a single universal-accuracy number.

The independent third-provider lane is HeliosPay. Its hand-authored ground
truth is stored before the run and includes 202 success handling, nested money,
query auth, extra operations, runtime errors, and webhook vectors.
