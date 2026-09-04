# Сравнение архитектур

## Рамка оценки

Сравниваются варианты из пользовательского запроса на официальном NovaPay
reference-case. Баллы ниже — ожидаемый результат по технической рубрике из
`описание.docx` (100 баллов), а не уже полученная оценка жюри. В расчёт включены
только функции, которые реально можно показать в рамках solo hackathon.

## Варианты

### A — прямые templates

`OpenAPI -> шаблоны -> Ruby`.

Парсер извлекает несколько полей, а ERB сам решает, какой endpoint считать
create/status/webhook. Быстро для одного YAML, но семантика размазана по
шаблонам и её трудно тестировать отдельно.

### B — structural IR

`OpenAPI -> Structural IR -> Ruby generator`.

IR нормализует operations, parameters, schemas, responses и refs. Генератор
становится детерминированным, но meaning `amount`, terminal statuses,
idempotency и webhook всё ещё приходится угадывать в одном большом слое.

### C — semantic Blueprint

`OpenAPI -> Structural IR -> analyzers -> Provider Blueprint -> decision gate ->
generator`.

Анализаторы не пишут Ruby напрямую: каждый сохраняет candidate, evidence,
score, conflicts и decision. Blueprint является стабильной границей между
исследованием и codegen.

## Ожидаемый score

| Критерий | A | B | C |
|---|---:|---:|---:|
| 1. Разбор API-спецификации / 20 | 13 | 17 | 19 |
| 2. Генерация интеграционного сервиса / 25 | 18 | 21 | 24 |
| 3. Корректность преобразования данных / 15 | 8 | 11 | 14 |
| 4. Универсальность и адаптируемость / 10 | 4 | 7 | 9 |
| 5. Документация и тестовые материалы / 13 | 9 | 11 | 12 |
| 6. Удобство использования и демонстрация / 10 | 9 | 9 | 9 |
| 7. Качество реализации / 10 | 6 | 8 | 9 |
| **Итого technical / 100** | **67** | **84** | **96** |

Доверительный диапазон: A ±5, B ±4, C ±3. Для C оставлен один балл запаса на
implementation defects; в `EXPECTED_SCORE.md` conservative model использует
95/100.

## Компромиссы

| Свойство | A | B | C |
|---|---|---|---|
| Correctness reference-case | базовые endpoints; money/webhook легко ошибиться | хорошая структурная полнота | покрывает все операции и safety policies |
| Универсальность | низкая: hidden provider assumptions | средняя: schema changes переживаются | высокая для supported patterns, unknown явно сообщаются |
| Объяснимость | низкая: reasoning в ERB | средняя | высокая: evidence ledger в Blueprint |
| Тестируемость | шаблонные snapshots | IR + snapshots | parser, analyzer, policy, codegen и domain layers отдельно |
| Hardcode risk | высокий | средний | низкий: hardcode только canonical vocabulary/policies |
| False semantic mapping | высокий | средний | контролируемый abstention |
| Расширяемость | добавление rules ломает templates | добавление IR fields безопаснее | новый analyzer/alias не меняет generator |
| Solo implementation effort | 12–16 h | 18–24 h | 26–34 h для MVP с golden case |

## Почему B не выбран

B — минимально хороший structural baseline. Он достаточно силён для discovery и
schema-preserving generation, но не имеет места, где честно выразить «единица
денег неизвестна» или «этот status нельзя безопасно сделать terminal». Это
приведёт либо к молчаливым догадкам, либо к разрастанию генератора и фактически
скрытому варианту C.

## Почему не выбрана четвёртая architecture

Вариант «C + runtime plugin DSL + web UI + generated tests» потенциально красив,
но его score gain появляется только после готового C и съедает время MVP. Эти
элементы оставлены bonus/backlog, а не признаны отдельной доминирующей
архитектурой.

## Решение

Берём C, но ограничиваем scope: один Blueprint schema, семь analyzers,
`OptionParser` CLI, ERB templates без semantic logic и обязательный gate
`ruby -c`/fixtures validation.
