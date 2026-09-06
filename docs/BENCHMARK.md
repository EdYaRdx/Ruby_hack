# Проверка универсальности и безопасности

Текущая проверка состоит из четырёх групп доказательств:

1. regression suite на RSpec;
2. reference mutation benchmark из 37 adversarial-кейсов, подготовленных
   авторами на основе NovaPay, где независимые semantic subsets сравниваются с
   фактическим Blueprint;
3. spec-only прогоны для официального NovaPay и mutation corpus;
4. независимая проверка Aurora и HeliosPay с заранее подготовленной ground truth
   и behavioral vectors.

Официальный `provider_api.yaml` NovaPay — reference input организатора. Сам
mutation benchmark — воспроизводимый corpus, подготовленный авторами, а не
набор тестов организатора и не заявление, что 37 мутаций представляют всех
провайдеров. Его ground truth находится в
[`research/benchmark/semantic_ground_truth.yml`](../research/benchmark/semantic_ground_truth.yml).
Aurora и HeliosPay — независимые provider-прогоны; их ground truth и behavioral
vectors находятся в [`fixtures/`](../fixtures/). Comparator проверяет не только
совпадение decision и отсутствие crash, но и независимые semantic subsets,
fail-closed safety и применимые generation/runtime gates.

## Определения метрик

Для `N` benchmark-кейсов:

- `decision_accuracy` = число кейсов, где actual decision совпадает с effective
  adjudicated decision, делённое на `N`;
- `safe_decision_coverage` = число кейсов, прошедших decision, independent
  semantics, safety и применимые generation/runtime gates, делённое на `N`;
- `automatic_coverage` (legacy) = число кейсов, прошедших только старый
  decision-only gate, делённое на `N`; это историческое сравнение, не показатель
  безопасности;
- `decision_automation_rate` = accepted decisions / total decisions. Старое поле
  `automatic_accept_rate` для отдельных кейсов сохраняется только в machine output
  для исторического сравнения и не должно использоваться как признак готовности;
- `review_required_rate` = фактические кейсы `REVIEW_REQUIRED` / `N`;
- `unknown_rate` = фактические кейсы `UNKNOWN` / `N`;
- `semantic_accept_accuracy` = кейсы с ожидаемым `ACCEPT`, у которых Blueprint
  независимо совпал с ground truth, / все кейсы с ожидаемым `ACCEPT`;
- accuracy каждой semantic area = совпавшие hand-authored subsets / число кейсов,
  где эта область объявлена релевантной;
- в aggregate эти области публикуются как `operation_semantic_accuracy`,
  `money_semantic_accuracy`, `status_semantic_accuracy`,
  `auth_semantic_accuracy`, `webhook_semantic_accuracy`,
  `idempotency_semantic_accuracy` и `field_mapping_semantic_accuracy`;
- `critical_false_accept_count` = критические кейсы, принятые с неверным или
  небезопасным semantic result;
- generation success считается только для кейсов, где генерация запускалась.

Старое decision-only automatic coverage сохраняется в machine result только для
исторического сравнения. Поле `automatic_accept_rate` не является judge-facing
метрикой автоматизации или безопасности.

## Актуальный автоматически сгенерированный результат

`bin/update_docs` запускает реальные benchmark scripts и RSpec, читает их JSON
results и заменяет только отмеченный ниже блок. Источники —
`tmp/benchmark/results.json`, `tmp/benchmark/second_provider.json` и JSON-отчёт
RSpec. Это воспроизводимые ignored artifacts, а не вручную отредактированные
утверждения.

<!-- BEGIN GENERATED: BENCHMARK -->
**Эталонный benchmark мутаций**

- Область: 37 adversarial-мутаций одного домена эталонного провайдера, а не 37 провайдеров.
- Независимые decision/semantic-кейсы пройдены: 37/37.
- Точность решений: 100.0%; точность semantic ACCEPT: 100.0%.
- Семантические области (operation / money / status / auth / webhook / idempotency / field mapping): 100.0% / 100.0% / 100.0% / 100.0% / 100.0% / 100.0% / 100.0%.
- Критических ложных ACCEPT: 0; генерация: 18/18 попыток пройдены.

**Прогоны только по спецификации**

- Официальный NovaPay baseline: автоматизация решений 10/14 (71.4%); доля review 4/14 (28.6%); blocking-записей 3; полностью готовых автоматически 0/1 (0.0%); критических ложных ACCEPT 0; попыток небезопасной генерации 0.
- NovaPay mutation lane: 7 кейсов, 98 решений; автоматизация решений 74/98 (75.5%); доля review 24/98 (24.5%); blocking-записей 17; полностью готовых автоматически 0/7 (0.0%); критических ложных ACCEPT 0; попыток небезопасной генерации 0.
- Aurora: автоматизация решений только по спецификации 13/15 (86.7%), полностью готовых автоматически 0/1 (0.0%); после разрешения полностью готовых автоматически 1/1 (100.0%); behavioral vectors 4/4.
- HeliosPay: автоматизация решений только по спецификации 12/14 (85.7%), полностью готовых автоматически 0/1 (0.0%); после разрешения полностью готовых автоматически 1/1 (100.0%); behavioral vectors 4/4.

Legacy `automatic_coverage` остаётся в machine results только для исторического сравнения. Это не judge-facing метрика автоматизации или безопасности.
<!-- END GENERATED: BENCHMARK -->

## Метрики на уровне решения и спецификации

Метрики для оценки используют разные знаменатели:

- `decision_automation_rate` = принятые решения / все решения;
- `review_rate` = решения `REVIEW_REQUIRED` / все решения;
- `fully_auto_ready_rate` = спецификации с нулём решений `REVIEW_REQUIRED` и
  нулём blocking-записей / все спецификации;
- `blocking_entries` считается отдельно, потому что одно решение может породить
  несколько blocking-записей;
- `critical_false_accepts` считает небезопасные `ACCEPT` в hand-authored
  критических кейсах;
- `unsafe_generation_attempts` считает попытки генерации при нерешённом
  критическом решении; значение равно нулю только когда runner доказывает,
  что такой попытки не было.

Автоматизация решений не равна готовности всей спецификации. В spec-only lane
могут быть приняты отдельные решения, но безопасная генерация всё ещё может быть
невозможна.

## Интерпретация

Высокая доля `ACCEPT` сама по себе недостаточна. Полезность системы определяется
тем, совпадает ли принятый Blueprint с независимой семантикой и не превращается
ли нерешённая критическая информация в скрытое сгенерированное значение. Поэтому
benchmark раздельно показывает correctness, safety и generation.

37-кейсовый reference benchmark NovaPay и spec-only lane — разные измерения.
Spec-only lane работает с пустыми provider defaults и сообщает автоматизацию
решений, долю review, blocking-записи, полную готовность спецификации и
метрики безопасности. Их нельзя сводить в одно число универсальной точности.

Независимый прогон третьего провайдера — HeliosPay. Его hand-authored ground
truth сохранена до запуска и включает обработку успеха `202`, вложенные деньги,
query-аутентификацию, дополнительные операции, runtime-ошибки и webhook-векторы.
