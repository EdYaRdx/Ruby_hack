# Red-team архитектуры: 30 adversarial cases

Дата: 2026-09-03

Цель red-team — проверить не красивую демонстрацию, а поведение компилятора в
ситуациях, где OpenAPI-структура и платёжная семантика расходятся. Каждая
строка должна иметь наблюдаемое решение: принять, запросить review, заблокировать
генерацию или сохранить неизвестное.

## Матрица случаев

| # | Случай | Классификация | Ожидаемое поведение | Генерация |
|---:|---|---|---|---|
| 1 | Schema говорит одно, description — другое | конфликт фактов | сохранить оба evidence, `CONFLICT` | блок до review |
| 2 | Description говорит «kopecks», пример выглядит как RUB | семантический конфликт | показать единицы и пример, не вычислять молча | review/block |
| 3 | Старый override против новой OpenAPI | stale override | fingerprint mismatch + `STALE_OVERRIDE` | блок |
| 4 | Денежная единица неизвестна | неизвестное | `money.unit=UNKNOWN`, запросить источник | блок для money adapter |
| 5 | Статус не входит в canonical map | неизвестное | сохранить raw status и предложить review | блок status projection |
| 6 | Статус одновременно выглядит terminal и transitional | конфликт классификации | `terminality=CONFLICT` | блок |
| 7 | Нет `operationId` | структурный gap | детерминированный кандидат из method/path, пометка | review; блок если неоднозначно |
| 8 | Path и operationId указывают на разные действия | конфликт mapper-ов | не выбирать по строковой близости; показать оба | блок |
| 9 | `POST /transactions` подходит и для create, и для capture | неоднозначный intent | несколько кандидатов с evidence | блок |
| 10 | Webhook endpoint есть, алгоритма обработки нет | неполная семантика | endpoint принять как fact, callback mapping unknown | блок webhook generation |
| 11 | Signature header есть, encoding не указан | криптографическая неизвестность | не угадывать hex/base64; warning + unknown | блок verification |
| 12 | API key location неизвестен или не поддерживается | auth gap | сохранить scheme, признать unsupported | блок |
| 13 | Bearer scheme без описания scope | auth с ограниченной семантикой | сгенерировать только транспортный bearer-кандидат | review |
| 14 | OAuth2/unsupported flow | unsupported construct | сохранить flow, не превращать в ApiKey | блок |
| 15 | Conditional required есть только в description | условное правило | candidate `required_if` с цитатой и provenance | review; блок ветки |
| 16 | Необычная фраза условия («for SBP only unless…») | неоднозначный prose | не расширять regex-эвристику без evidence | review/block |
| 17 | Сломанный `$ref` | невалидный вход | диагностировать путь ссылки и место ошибки | блок ingest |
| 18 | Рекурсивный `$ref` в неподдерживаемой позиции | parser safety | bounded resolution, cycle diagnostic | блок affected schema |
| 19 | Local/external `$ref` не разрешается | reproducibility gap | fingerprint inputs + diagnostic; не подменять пустой схемой | блок |
| 20 | Неизвестная конструкция OpenAPI | forward compatibility | сохранить raw fragment/diagnostic | review или block по impact |
| 21 | `GET /balance` — extra operation | вне canonical contract | поместить в `extra_operations` | не терять, не force-map |
| 22 | Два endpoint-а подходят для `fetch_status` | ambiguous projection | попросить selection rule; оба кандидата видимы | блок |
| 23 | Status mapping отсутствует | неполная семантика | применять только `CASE_DEFAULT`, если case scope подтверждён | review и provenance |
| 24 | `request_method` неясен | contract ambiguity | отделить HTTP method от logical host action | блок profile |
| 25 | `BaseService` отсутствует | environment gap | использовать test-only stub/profile, не invent production helpers | блок production claim |
| 26 | Spec изменился после review | freshness conflict | новый spec fingerprint invalidates dependent resolutions | блок regeneration |
| 27 | Card и SBP имеют разные required fields | conditional branches | выделить mutually exclusive branches и validate each | review/block incomplete branch |
| 28 | Сумма в major units | money interpretation | не умножать без explicit `amount_unit=major` | review; block if ambiguous |
| 29 | Сумма в minor units | money interpretation | хранить conversion policy + provider unit | accept only with evidence |
| 30 | Сумма — decimal string | representation vs unit | различить type/format/unit; decimal parsing is not unit proof | review/block |

## Политика классификации

`BLOCK` означает, что детерминированная generation затронутого adapter-а
небезопасна. Это не означает, что весь документ нельзя разобрать: unaffected
facts и extra operations должны сохраниться. `REVIEW` означает, что candidate
можно показать человеку, но до подтверждения он не считается resolved Blueprint.

Нельзя превращать отсутствие evidence в «низкую вероятность» и затем
генерировать. Для критических областей (`money`, `auth`, `status`, `webhook`,
`request_method`, conditional required) действует abstention.

## Обязательные diagnostics

Каждая unresolved запись содержит:

- стабильный `decision_id`;
- affected JSON Pointer/path и operation/field;
- proposed value (если есть);
- raw evidence excerpts и source (`SPEC_FACT`, `CASE_DEFAULT`, etc.);
- conflicts и fingerprint spec/override;
- severity (`WARNING`/`BLOCKING`);
- action (`confirm`, `remap`, `supply_override`, `exclude`).

Задача red-team считается пройденной только когда эти diagnostics проверяемы
в fixture-тестах; prose-обещание в документации не является прохождением.

## Что это исключает

- fuzzy match как самостоятельное основание для платёжной семантики;
- silent default для signature encoding, money units и terminal statuses;
- потерю endpoint-ов, которые не подходят под canonical contract;
- неявную зависимость от private methods недоступного `BaseService`;
- regeneration поверх изменившегося spec без stale detection.
