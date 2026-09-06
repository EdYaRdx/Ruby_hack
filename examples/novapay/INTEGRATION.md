# Интеграция NovaPay

Сгенерировано из Provider Blueprint v1.

- Sandbox URL: https://api.sandbox.novapay.example/v1
- Базовый URL runtime: `NOVAPAY_BASE_URL` (по умолчанию используется sandbox URL)
- Аутентификация: ApiKeyAuth
- Сумма: major RUB -> kopecks; scale 100; request factor 100
- Обязательность Idempotency по спецификации: false
- Подпись webhook: HMAC-SHA256 / hex
- Действия callback: {"approved" => "approve_operation", "rejected" => "reject_operation", "in_progress" => nil}
- Дополнительные operations: /payouts/{payout_id}/cancel, /balance

## Endpoint-ы

- `POST /payouts` - createPayout -> create_request
- `GET /payouts/{payout_id}` - getPayoutStatus -> fetch_status
- `POST /payouts/{payout_id}/cancel` - cancelPayout - EXTRA_OPERATION
- `POST /webhooks/payout` - payoutWebhook -> process_callback
- `GET /balance` - getBalance - EXTRA_OPERATION

## Маппинг статусов

| Статус провайдера | Space Payments |
|---|---|
| `pending` | `in_progress` |
| `processing` | `in_progress` |
| `completed` | `approved` |
| `failed` | `rejected` |
| `cancelled` | `rejected` |

Источник: resolved Provider Blueprint `statuses`.

## Дополнительные operations

Endpoint-ы без явного profile binding не становятся BaseService methods:

- `POST /payouts/{payout_id}/cancel` (`cancelPayout`): `EXTRA_OPERATION`, preserved, non-blocking
- `GET /balance` (`getBalance`): `EXTRA_OPERATION`, preserved, non-blocking

## ProviderGateway / конфигурация

- Service class: `Provider::NovapayService`; BaseService: `Provider::BaseService`
- Окружения и base URL:
- sandbox: `https://api.sandbox.novapay.example/v1`
- production: `https://api.novapay.example/v1`
- Auth strategy: `ApiKeyAuth` (`api_key` / `header` / `X-API-Key`)
- API key/config parameter: `X-API-Key`; runtime URL override: `NOVAPAY_BASE_URL`
- Webhook secret: передаётся в generated adapter, если Blueprint содержит signature semantics (`X-NovaPay-Signature`)
- Idempotency по спецификации: `false`; adapter policy: `if_available`; header: `Idempotency-Key`
- BaseService methods: `check_conditions`, `create_request`, `process_callback`, `fetch_status`
- Host operation source: `operation.id`, `operation.amount`, `operation.payout_requisite`

Параметры, которые необходимо передать в окружение/host gateway, должны
быть адаптированы к API host-приложения; этот generated документ не
объявляет production framework contract, которого нет в Blueprint.

## Host input и request_method

Host operation передаёт идентификатор, сумму и `payout_requisite`.
Ветки реквизитов и provider-поля:

- `request_method=sbp`: `operation.payout_requisite["sbp"]["phone"]` → `recipient.phone`
- `request_method=sbp`: `operation.payout_requisite["sbp"]["bank_code"]` → `recipient.bank_code`
- `request_method=sbp`: `operation.payout_requisite["sbp"]["bank_name"]` → `recipient.bank_name`
- `request_method=card`: `operation.payout_requisite["card_number"]` → `recipient.card_number`
- `request_method=card`: `operation.payout_requisite["phone"]` → `recipient.phone`

`request_method` — логический способ выплаты, поддерживаемые значения:
`sbp`, `card`. Это не HTTP method и
не имя BaseService operation `create_request`; HTTP method/path указаны
в разделе endpoint-ов. Не предполагаются flat top-level поля
`operation.recipient_phone`, `operation.bank_code` или
`operation.card_number`.

## Результат create и persistence

Успешный create возвращает `success(result: { id: provider_operation_id })`.
Provider operation id сохраняется платформой Space Payments; generated
service не владеет persistence или состоянием host operation.

## Маппинг статусов и helpers

| Provider status | Space Payments | Host action |
|---|---|---|
| `pending` | `in_progress` | `нет terminal helper` |
| `processing` | `in_progress` | `нет terminal helper` |
| `completed` | `approved` | `approve_operation` |
| `failed` | `rejected` | `reject_operation` |
| `cancelled` | `rejected` | `reject_operation` |

## Проверка request и ошибки

Сгенерированный адаптер проверяет обязательные поля, enums, patterns, lengths,
conditional payout requisite fields и host-side minimum amount до отправки.
HTTP-ошибки возвращаются без blind retries; POST retries после rate limit
должны повторно использовать тот же idempotency key. Если host не передал
`operation.idempotency_key`, fallback key хранится только в памяти процесса;
durability across process restart не гарантируется.

Provider condition → platform failure code → i18n key:

| Provider condition | Platform code | i18n key |
|---|---|---|
| HTTP 400 | `bad_request` | `provider.validation_error` |
| HTTP 401 | `unauthorized` | `provider.invalid_credentials` |
| HTTP 402 | `unprocessable_entity` | `provider.insufficient_balance` |
| HTTP 404 | `not_found` | `provider.not_found` |
| HTTP 409 | `unprocessable_entity` | `provider.conflict` |
| HTTP 422 | `unprocessable_entity` | `provider.validation_error` |
| HTTP 429 | `too_many_requests` | `provider.rate_limit` |
| HTTP 500 | `internal_server_error` | `provider.internal_error` |
| HTTP 502 | `internal_server_error` | `provider.transport_error` |
| provider `amount_limit_exceeded` | `unprocessable_entity` | `provider.amount_limit_exceeded` |



Обработка webhook использует fail-closed поведение, если raw body,
signature, secret или known event outcome отсутствуют либо некорректны.
Подпись проверяется по исходному raw body; JSON не пересобирается для HMAC.

Сгенерированный Ruby является проекцией resolved Blueprint. Перед production
use проверьте решения review и контракт host BaseService.
