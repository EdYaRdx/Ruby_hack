# Независимая проверка Aurora Transfers

> Current semantic validation snapshot. Aurora — synthetic fixture provider, а
> не production provider. Для текущего runtime transport evidence используйте
> [`docs/BENCHMARK.md`](../docs/BENCHMARK.md) и
> [`GOAL_6_5_RESULT.md`](GOAL_6_5_RESULT.md).

Provider: Aurora Transfers

Провайдер — намеренно независимая синтетическая/reference OpenAPI fixture, а не
переименованный документ NovaPay. Его ground truth, подготовленная авторами,
создана в `fixtures/aurora_ground_truth.yml` до запуска compiler. Машиночитаемый
`semantic_subset` из этого файла сравнивается напрямую с resulting Blueprint;
одного равенства top-level decision недостаточно.

## Отличия от NovaPay

| Область | Aurora Transfers |
|---|---|
| Операция создания | `POST /transfers`, `initiateTransfer` |
| Операция статуса | `GET /transfers/{transfer_id}`, `getTransferState` |
| Аутентификация | Bearer token в `Authorization` |
| Деньги | вложенные `money.value` и `money.currency`, major USD в виде decimal string |
| Статусы | `queued`, `settled`, `declined`, `voided` |
| Webhook | `POST /notifications`, `X-Aurora-Signature` |
| Получатель | `destination` с conditional fields для bank/card |
| Idempotency | необязательный `X-Aurora-Request-Token` |
| Дополнительно | `/transfers/{transfer_id}/void` и `/limits` |

## Уровни resolution

Harness фиксирует все три требуемых уровня. Средний уровень выделен явно, хотя
текущая реализация хранит безопасные повторно используемые provider-neutral rules
в общем analyzer, поэтому его input такой же, как у pure-generic run.

| Уровень | Input сверх BaseServiceProfile | Результат | Blocking | Генерация |
|---|---|---|---:|---|
| A. Pure generic | none | `REVIEW_REQUIRED` | 1 | not attempted |
| B. Generic + safe reusable rules | built-in provider-neutral rules | `REVIEW_REQUIRED` | 1 | not attempted |
| C. Generic + minimal provider-specific resolution | four explicit sections | `ACCEPT` | 0 | syntax and smoke PASS |

Все три уровня прошли независимый semantic comparator. Level C также прошёл
четыре hand-authored behavioral vectors.

### Pure generic level

Команда:

```powershell
bundle exec ruby research/benchmark/second_provider.rb
```

Только с `BaseServiceProfile` и empty case defaults настоящий compiler
автоматически разрешил:

- create, status и notification operation roles;
- Bearer authentication;
- nested major-unit money и identity conversion;
- `destination` и extra-operation structure.

Он вернул `REVIEW_REQUIRED` с одним blocking decision, поскольку provider status
aliases и webhook raw-body/signature encoding не были подтверждены
profile/default. Generation на этом уровне не запускалась.

### Safe reusable rules level

Этот уровень намеренно не является скрытым provider-specific rules file.
Встроенные synonym candidates остаются review-only для critical status
semantics, а неизвестные webhook raw-body/encoding details остаются blocking.
Это подтверждает, что повторно используемые общие rules улучшают объяснение, не принимая
молча Aurora-specific meanings.

### Resolved level

Минимальный provider-specific resolution file содержит четыре раздела:

- money representation metadata;
- status map;
- webhook raw-body/hex policy;
- nested request/response field mappings.

Полученная Blueprint имеет `ACCEPT`, нулевые blocking/review decisions, а generated
artifacts проходят syntax, contract smoke и localhost HTTP transport verification:

- `tmp/benchmark/aurora-generic_plus_case_defaults/provider_blueprint.json`;
- `tmp/benchmark/aurora-generic_plus_case_defaults/service.rb`;
- `tmp/benchmark/aurora-generic_plus_case_defaults/contract_smoke.rb`.

Readiness сохраняет `runtime_transport.status = PASS`, а внешний provider
sandbox остаётся `NOT_EXECUTED`.

Smoke contract проверяет nested request projection, decimal same-unit money,
Bearer auth, обработку notification signature и callback status processing.

Semantic comparator независимо проверил resolved Blueprint для:

- `create_request` → `POST /transfers`;
- `fetch_status` → `GET /transfers/{transfer_id}`;
- Bearer header auth;
- `money.value` / `money.currency`, major-to-major scale `1`;
- `queued`/`settled`/`declined`/`voided` status mappings;
- `POST /notifications`, `X-Aurora-Signature`, HMAC-SHA256, raw body и hex;
- optional `X-Aurora-Request-Token` с adapter-policy provenance;
- preserved non-blocking `voidTransfer` и `getTransferLimits` extras.

## Независимые behavioral vectors

Vectors подготовлены авторами в `fixtures/aurora_behavioral_vectors.yml` и не
генерируются из Blueprint. Результаты generated service:

| Вектор | Ожидаемое поведение | Результат |
|---|---|---|
| Host create input | nested request body, Bearer auth, optional token header, sandbox URL | PASS |
| Provider status response | `settled` → canonical `approved`, amount `12.50` | PASS |
| Settled webhook | approved status and `approve_operation` | PASS |
| Declined webhook | rejected status and `reject_operation` | PASS |

Три resolution levels прошли semantic comparison (`3/3`), все четыре behavioral
vectors прошли (`4/4`), critical false ACCEPTs равны `0`.

## Стоимость resolution и вывод

Pure generic engine успешно находит core operation/auth/nested money, а при
critical unresolved semantics выполняет abstention. На resolved level достаточно
четырёх explicit provider sections; provider-specific branch в generic code не
добавлялась. Конкретная ошибка второго provider выявила flat-body assumption в
projection; она заменена на Blueprint-driven nested mapping. Frozen pipeline и
границы stages не изменились.

Это не live network integration test; credentials и provider network calls
намеренно находятся вне scope.
