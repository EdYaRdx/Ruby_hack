# Контракт Space Payments для Provider Compiler

Этот документ фиксирует host-контракт, который используется текущим
`space_payments_v1` profile. Он описывает вход и результат адаптера, а не
внутреннюю модель конкретного provider.

## Поля host operation

Минимальная host operation использует:

| Поле | Назначение |
|---|---|
| `operation.id` | идентификатор операции host; он передаётся как provider external id, если это предусмотрено Blueprint |
| `operation.amount` | сумма в canonical host unit; для Space Payments это major RUB |
| `operation.payout_requisite` | JSONB/hash с реквизитами выплаты |
| `request_method` | логический способ выплаты, например `sbp` или `card` |

Для SBP реквизиты находятся во вложенной ветке:

```ruby
operation.payout_requisite["sbp"]["phone"]
operation.payout_requisite["sbp"]["bank_code"]
operation.payout_requisite["sbp"]["bank_name"] # если нужен provider
```

Для карты используется плоское поле внутри `payout_requisite`:

```ruby
operation.payout_requisite["card_number"]
```

Space Payments не гарантирует `operation.payout_requisite["phone"]` для карты.
Если provider требует дополнительный card phone, а profile не содержит явного
host mapping, решение остаётся `REVIEW_REQUIRED` и генерация блокируется.

Контракт не гарантирует плоские top-level поля
`operation.recipient_phone`, `operation.bank_code` или
`operation.card_number`. Adapter/profile может спроецировать provider-поля из
`payout_requisite`, но не должен молча считать эти поля частью host API.

## Создание операции и persistence boundary

Успешный `create_request` возвращает provider id в стандартной форме:

```ruby
success(result: { id: provider_operation_id })
```

Сервис формирует request и нормализует response. Persistence provider id,
связь с host operation и изменение состояния операции принадлежат платформе
Space Payments, а не сгенерированному provider service.

`request_method` не является HTTP-методом и не означает вызов `create`.
Это логический host payment method (`sbp`, `card` и т. п.); HTTP method и
provider path задаются отдельным operation mapping. В частности,
`request_method=sbp` может использоваться при `POST /payouts`.

Ошибки возвращаются через host failure contract:

```ruby
failure(code, i18n_key)
```

Набор допустимых platform codes и их `i18n_key` определяется profile. Provider
условия не должны превращаться в произвольные статус, code и message-тройки.

## Статусы и callback helpers

Provider status нормализуется в canonical status. Для terminal callback
используются host helpers:

| Canonical status | Действие |
|---|---|
| `approved` | `approve_operation` |
| `rejected` | `reject_operation` |
| `in_progress` | terminal helper не вызывается |

Callback получает parsed payload и metadata, включая исходный `raw_body`,
signature header и secret. Подписываемые данные — именно raw body; JSON не
пересобирается перед HMAC-проверкой.

## Неизвестные реквизиты

Если обязательное provider-реквизитное поле не удаётся надёжно сопоставить с
host source, оно сохраняется как evidence и переводится в Review/неразрешённый
пункт. Нельзя выполнять blind lookup, подставлять top-level recipient или
генерировать небезопасный mapping без явного решения profile/человека.

## Лимиты

`amount_limit_exceeded` означает проверку/ограничение суммы конкретной
операции и обычно маппится в validation/rejection. Это не утверждение о
дневном лимите, ручном review оператора или состоянии provider balance.

## Связанные документы

- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — граница host projection и provider transport;
- [`docs/DEMO.md`](DEMO.md) — сценарий jury-facing Demo Workbench;
- generated `INTEGRATION.md` — конкретный resolved mapping для provider.
