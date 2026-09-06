# Jury FAQ

## Где сохраняется provider operation id?

`create_request` возвращает `success(result: { id: ... })`. Сам provider id и
связь с host operation сохраняет Space Payments; generated service не владеет
базой данных и состоянием операции.

## Что означает `request_method`?

Это логический способ выплаты (`sbp`, `card`), а не HTTP method и не имя
операции `create`. Например, `request_method=sbp` может приводить к
`POST /payouts`.

## Где находятся payout requisites?

В `operation.payout_requisite`. Для SBP используются вложенные
`["sbp"]["phone"]` и `["sbp"]["bank_code"]`; для карты —
`["card_number"]` внутри `payout_requisite`. Плоские top-level recipient-поля
не предполагаются.

## Что происходит с неизвестным обязательным полем?

Система сохраняет evidence, показывает unresolved item и fail-closed блокирует
небезопасную генерацию. Она не угадывает поле и не делает blind lookup.

## Как статус доходит до host?

Provider status нормализуется в canonical status. `approved` вызывает
`approve_operation`, `rejected` — `reject_operation`, а `in_progress` не
вызывает terminal helper.

## Как проверяется HMAC webhook?

Подпись проверяется по исходному `raw_body` и соответствующему secret с
указанными algorithm/encoding. JSON для вычисления подписи не пересобирается.

## Почему в Demo используется localhost HTTP?

Это воспроизводимая проверка generated adapter через реальный локальный socket:
метод, path, query, auth, body и response parsing фиксируются без credentials.
Внешний provider sandbox в checkout не вызывается.

## Почему интеграция не всегда полностью автоматическая?

OpenAPI хорошо описывает transport и schema, но не всегда задаёт бизнес-смысл
денег, статусов, реквизитов и callback actions. Критическая неоднозначность
переходит в Review, чтобы человек подтвердил mapping до generation.
