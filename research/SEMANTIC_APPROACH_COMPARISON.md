# Сравнение semantic approaches

> **ИСТОРИЧЕСКАЯ ИДЕЯ — НЕ ИСПОЛЬЗУЕТСЯ В ТЕКУЩЕМ ПРОТОТИПЕ.** Это раннее
> плановое сравнение подходов и его benchmark numbers не являются текущими
> результатами. Актуальные проверки находятся в [`docs/BENCHMARK.md`](../docs/BENCHMARK.md).

## Интерпретация benchmark

В `research/benchmark/mutations.json` 37 мутаций официальной спецификации. Каждая
имеет label `ACCEPT`, `REVIEW_REQUIRED` или `UNKNOWN`; label описывает безопасное
решение, а не вероятность. `ACCEPT` разрешает codegen, `REVIEW_REQUIRED` требует
человеческого override, `UNKNOWN` блокирует автоматическую генерацию.

Метрики:

- `ACCEPT precision` = correct ACCEPT / all ACCEPT;
- `safe decision coverage` = correct ACCEPT или correct REVIEW / 37; корректный
  возврат `UNKNOWN` безопасен, но не считается coverage;
- `critical false accepts` = ACCEPT на мутации с safety-critical label, где
  ожидается review/unknown;
- `auto-accept rate` = all ACCEPT / 37;
- `review` и `unknown` — абсолютные counts.

Результаты ниже — воспроизводимый policy-emulator benchmark по разметке mutation
set, а не измерение production parser. Имена подходов означают разные policy
на одних и тех же входах.

## Aggregate result

| Подход | ACCEPT | Precision | Safe coverage | Review | Unknown | Critical false accepts | Сложность | Время |
|---|---:|---:|---:|---:|---:|---:|---|---:|
| 1. Exact deterministic rules | 7 | 100.0% | 32.4% | 5 | 25 | 0 | низкая | 4–6 h |
| 2. Domain dictionaries + rules | 19 | 78.9% | 73.0% | 12 | 6 | 4 | низко-средняя | 8–12 h |
| 3. Rules + lexical aliases | 24 | 62.5% | 59.5% | 10 | 3 | 9 | средняя | 10–14 h |
| 4. Rules + fuzzy lexical similarity | 29 | 58.6% | 56.8% | 4 | 4 | 12 | средне-высокая | 14–20 h |
| 5. Rules + schema/structure | 23 | 73.9% | 64.9% | 8 | 6 | 6 | средняя | 12–16 h |
| 6. Hybrid без abstention | 32 | 53.1% | 45.9% | 0 | 5 | 15 | высокая | 18–24 h |
| **7. Hybrid + abstention** | **17** | **100.0%** | **89.2%** | **16** | **4** | **0** | **средне-высокая** | **20–28 h** |

Числа агрегируются скриптом `benchmark/aggregate.ps1`; safe coverage считает
только точные ожидаемые решения, поэтому штрафует как опасный ACCEPT, так и
неуместное REVIEW/UNKNOWN. Процент округляется до одной десятой.

## Critical false accepts по safety class

| Подход | money units | idempotency | retry safety | webhook signature | final statuses | auth assumptions | total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Exact | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Dictionaries | 0 | 0 | 1 | 0 | 3 | 0 | 4 |
| Lexical | 2 | 0 | 4 | 0 | 3 | 0 | 9 |
| Fuzzy | 4 | 0 | 3 | 0 | 5 | 0 | 12 |
| Schema/structure | 3 | 0 | 1 | 0 | 2 | 0 | 6 |
| Hybrid no abstention | 4 | 1 | 4 | 1 | 5 | 0 | 15 |
| **Hybrid + abstention** | **0** | **0** | **0** | **0** | **0** | **0** | **0** |

## Выводы

1. Exact rules безопасны, но слишком много обычных изменений оставляют как
   `UNKNOWN`; это ухудшает criterion universality и делает demo слабее.
2. Lexical aliases восстанавливают варианты path/operation, но `sum`, `total`,
   `success`, `voided` и transfer/withdrawal names не доказывают payment
   semantics. Blind acceptance создаёт именно те false accepts, за которые
   rubric штрафует сильнее всего.
3. Schema/structure необходимы, но не устанавливают unit или retry safety,
   когда в spec отсутствует relevant annotation.
4. Winning policy — не просто «больше scoring», а способность abstain на safety
   boundary. Top1-top2 margin помогает объяснить decision, но critical evidence
   gates могут переопределить высокий score.

## Выбранная decision policy

Рекомендуемые starting thresholds, которые нужно recalibrate по mutation set:

- hard conflict or unresolved reference -> `UNKNOWN`;
- any critical decision without explicit evidence -> `REVIEW_REQUIRED`;
- `ACCEPT` only when score >= 8/10, margin >= 2 points, and no hard/critical
  conflict;
- score 5–7 or margin < 2 -> `REVIEW_REQUIRED`;
- score <= 4 -> `UNKNOWN`.

Это decision thresholds, а не probabilities. Benchmark должен падать в CI, если
critical false accepts становятся ненулевыми, даже при росте aggregate coverage.

## Что в продукте остаётся эмпирическим

Этот результат выбирает MVP policy. Он не доказывает performance на arbitrary
OpenAPI documents. Во время implementation добавьте минимум две unseen
provider-like fixtures и повторите ту же mutation suite; thresholds могут
измениться, но zero-critical-false-accept invariant должен сохраниться.
