# Проверка универсальности и безопасности

Текущая validation состоит из трёх независимых gates:

1. regression suite на RSpec;
2. mutation benchmark из 37 кейсов NovaPay, где hand-authored semantic
   subsets сравниваются с фактической Blueprint;
3. semantic comparison второго провайдера Aurora и hand-authored behavioral
   vectors.

Mutation benchmark — воспроизводимый corpus, а не заявление, что 37 mutations
представляют всех провайдеров. Его ground truth находится в
[`research/benchmark/semantic_ground_truth.yml`](../research/benchmark/semantic_ground_truth.yml).
Ground truth и vectors Aurora находятся в [`fixtures/`](../fixtures/).

## Определения метрик

Для `N` benchmark cases:

- `decision_accuracy` = число кейсов, где actual decision совпадает с effective
  adjudicated decision / `N`;
- `safe_decision_coverage` = число кейсов, прошедших decision, independent
  semantics, safety и применимые generation/runtime gates / `N`;
- `automatic_accept_rate` = actual `ACCEPT` cases / `N`;
- `review_required_rate` = actual `REVIEW_REQUIRED` cases / `N`;
- `unknown_rate` = actual `UNKNOWN` cases / `N`;
- `semantic_accept_accuracy` = expected `ACCEPT` cases с независимо совпавшей
  Blueprint / expected `ACCEPT` cases;
- accuracy каждой semantic area = совпавшие hand-authored subsets / число
  кейсов, где эта area объявлена релевантной;
- `critical_false_accept_count` = critical cases, принятые с неверной или
  небезопасной semantic result;
- generation success считается только для кейсов, где generation запускалась.

Старое decision-only automatic-coverage сохраняется в machine result для
исторического сравнения. Оно не является safety metric.

## Актуальный автоматически сгенерированный результат

`bin/update_docs` запускает реальные benchmark scripts и RSpec, читает их JSON
results и заменяет только отмеченный ниже блок. Источники —
`tmp/benchmark/results.json`, `tmp/benchmark/second_provider.json` и JSON-отчёт
RSpec. Это воспроизводимые ignored artifacts, а не вручную отредактированные
утверждения.

<!-- BEGIN GENERATED: BENCHMARK -->
**Mutation benchmark NovaPay**

- Кейсы: пройдено 37/37.
- Decision accuracy: 100.0%.
- Automatic ACCEPT rate: 48.6%.
- Safe decision coverage: 100.0%.
- REVIEW_REQUIRED rate: 40.5%; UNKNOWN rate: 10.8%.
- Semantic ACCEPT accuracy: 100.0%.
- Operations / money / statuses / auth / webhook / idempotency / field mappings: 100.0% / 100.0% / 100.0% / 100.0% / 100.0% / 100.0% / 100.0%.
- Critical false ACCEPTs: 0.
- Generation: успешно 18/18 попыток; generated Ruby syntax pass rate: 100.0%.
- Второй provider Aurora: semantic levels 3/3, behavioral vectors 4/4; semantic accuracy: 100.0%; critical false ACCEPTs: 0.

Legacy decision-only automatic-coverage: 100.0%. Значение оставлено для сравнения и не используется как safety gate.
<!-- END GENERATED: BENCHMARK -->

## Интерпретация

Высокий accept rate сам по себе недостаточен. Полезность системы определяется
тем, совпадают ли accepted Blueprint с независимой семантикой и не превращается
ли нерешённая critical information в скрытое generated value. Поэтому benchmark
раздельно показывает correctness, safety и generation.
