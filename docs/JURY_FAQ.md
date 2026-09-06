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

## Почему NovaPay spec-only не fully-auto ready?

Официальная NovaPay spec-only проверка автоматически разрешает 10 из 14
semantic decisions. Полная integration readiness — бинарная проверка: одного
неразрешённого critical decision достаточно, чтобы generation была заблокирована.
Это fail-closed safety policy, а не отсутствие generator.

## 37/37 — это 37 providers?

Нет. Это 37 adversarial mutation cases одного reference provider domain.
Они проверяют regression и semantic safety; отдельные provider lanes проверяются
на NovaPay, Aurora и HeliosPay.

## 12/12 — это 12 providers?

Нет. Это 12 frozen black-box cases с разными OpenAPI shapes и safety scenarios.
Они не являются выборкой из 12 production providers.

## Где доказательство универсальности?

Здесь заявляется bounded universality: общий pipeline проверен на official NovaPay,
synthetic Aurora, synthetic HeliosPay, frozen black-box corpus и произвольной
OpenAPI upload lane. Это воспроизводимое evidence по committed provider shapes,
а не обещание поддержки любого OpenAPI.

## Совместимость с production Space Payments доказана?

Нет, production acceptance честно не заявляется. В checkout нет реального
production `Provider::BaseService`, client/result objects, staging environment или
provider credentials; для verification используется локальный stub/harness.

## Adapter отправляет настоящий HTTP-запрос?

Да, generated adapter проходит localhost HTTP E2E через реальный socket.
Проверяются method, path, query, auth, body, content type, response parsing и
status mapping; внешний provider sandbox при этом не вызывается.

## Почему не использовать OpenAPI Generator?

OpenAPI Generator строит API client или SDK. Provider Compiler решает другую
задачу: сопоставляет provider API с business contract Space Payments, включая
money, statuses, auth, webhooks, errors, idempotency и safety decisions.

## Зачем нужен human review?

OpenAPI может сказать `amount: integer`, но не сказать major это или minor units,
какой scale применять и как интерпретировать currency. В payment domain безопаснее
один раз подтвердить mapping, чем молча изменить реальную сумму выплаты.
