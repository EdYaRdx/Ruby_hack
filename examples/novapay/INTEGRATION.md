# Интеграция NovaPay

Сгенерировано из Provider Blueprint v1.

- Sandbox URL: https://api.sandbox.novapay.example/v1
- Runtime base URL: `NOVAPAY_BASE_URL` (по умолчанию используется sandbox URL)
- Аутентификация: ApiKeyAuth
- Сумма: major RUB -> kopecks; scale 100; request factor 100
- Обязательность Idempotency по spec: false
- Подпись webhook: HMAC-SHA256 / hex
- Действия callback: {"approved" => "approve_operation", "rejected" => "reject_operation", "in_progress" => nil}
- Дополнительные operations: /payouts/{payout_id}/cancel, /balance

## Endpoints

- `POST /payouts` - createPayout -> create_request
- `GET /payouts/{payout_id}` - getPayoutStatus -> fetch_status
- `POST /payouts/{payout_id}/cancel` - cancelPayout - EXTRA_OPERATION
- `POST /webhooks/payout` - payoutWebhook -> process_callback
- `GET /balance` - getBalance - EXTRA_OPERATION

## Проверка request и ошибки

Сгенерированный adapter проверяет required fields, enums, patterns, lengths,
conditional recipient fields и host-side minimum amount до отправки.
HTTP errors возвращаются без blind retries; POST retries после rate limit
должны повторно использовать тот же idempotency key.

- HTTP 400: validation_error
- HTTP 401: unauthorized → unauthorized
- HTTP 402: insufficient_balance → insufficient_balance
- HTTP 409: conflict
- HTTP 422: validation_error → validation_error
- HTTP 429: rate_limit_exceeded → rate_limit_exceeded (сохранять Retry-After)
- HTTP 500: internal_error
- HTTP 404: not_found → not_found
- HTTP 409: invalid_status → conflict

Webhook processing использует fail-closed поведение, если raw body,
signature, secret или known event outcome отсутствуют либо некорректны.

Сгенерированный Ruby является проекцией resolved Blueprint. Перед production
use проверьте review decisions и host BaseService contract.
