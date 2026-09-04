# Эталонный ground truth: NovaPay provider_api.yaml

Источник: official `provider_api.yaml`, OpenAPI `3.0.3`,
root-document SHA-256 `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551`.
Этот root hash — только идентификатор исходного файла. Runtime fingerprint
Blueprint должен считаться по root document плюс полной транзитивной closure
разрешённых local `$ref` и версии resolver policy.
Ниже разделены значения, присутствующие в документе, и выводы, которые нужен
для генератора, но не являются буквальным OpenAPI fact.

## Метаданные provider-а

- `info.title`: `NovaPay Payout API`.
- `info.version`: `1.0.0`.
- Servers: sandbox `https://api.sandbox.novapay.example/v1` и production
  `https://api.novapay.example/v1`.
- Tags: `Payouts` и `Webhooks`.

## Операции

| operationId | Method/path | Auth | Request | Success response |
|---|---|---|---|---|
| `createPayout` | POST `/payouts` | `ApiKeyAuth` | required JSON `CreatePayoutRequest`; optional `Idempotency-Key` | 201 `PayoutResponse` |
| `getPayoutStatus` | GET `/payouts/{payout_id}` | `ApiKeyAuth` | required path string `payout_id` | 200 `PayoutResponse` |
| `cancelPayout` | POST `/payouts/{payout_id}/cancel` | `ApiKeyAuth` | required path string `payout_id` | 200 `PayoutResponse` |
| `payoutWebhook` | POST `/webhooks/payout` | `security: []` | required JSON `WebhookPayload`; required signature header | 200 object `{received: boolean}` |
| `getBalance` | GET `/balance` | `ApiKeyAuth` | no request body | 200 inline object `{balance, currency, hold}` |

## Auth и headers

- `ApiKeyAuth`: OpenAPI `apiKey`, `in: header`, name `X-API-Key`.
- Параметр create `IdempotencyKey`: header `Idempotency-Key`, optional,
  `string`, `format: uuid`; description говорит о предотвращении дубликатов.
- Параметр webhook: header `X-NovaPay-Signature`, обязательная строка;
  description говорит, что это HMAC-SHA256 подпись тела request.
- `security: []` у webhook — явное отсутствие API-key security у этой
  operation, а не указание пропустить HMAC verification.

## Schemas и поля

### `CreatePayoutRequest`

Обязательные поля: `amount`, `currency`, `external_id`, `recipient`.

- `amount`: integer, minimum `100000`, description `Сумма в копейках`, example
  `1500000`.
- `currency`: string, enum `[RUB]`.
- `external_id`: string, maxLength 64, merchant-side operation ID.
- `recipient`: `$ref` to `Recipient`.

### `Recipient`

Обязательные поля: `type`, `phone`.

- `type`: string, enum `[sbp, card]`.
- `phone`: string, regex `^7\d{10}$`, 11 digits starting with 7.
- `bank_code`: string; description говорит, что поле обязательно при `type=sbp`.
- `bank_name`: string, example `Сбербанк`.
- `card_number`: string; description говорит, что поле обязательно при `type=card`.

Последние два conditional rules не выражены через `oneOf`/discriminator.

### `PayoutResponse`

Поля: `id`, `external_id`, `status`, `amount`, `currency`, `recipient`,
`error`, `created_at`, `completed_at`. `status` enum имеет значения
`[pending, processing, completed, failed, cancelled]`. `amount` — integer с
example `1500000`, но сама schema не повторяет описание unit.
Для reference case provider-side amount — minor RUB units (kopecks).
Целевой `operation.amount` в Space Payments — major RUB, поэтому request
projection — `major -> minor`, умножение на `100`; response projection — обратное
преобразование, деление на `100`. Это отдельные evidence records: provider unit
подтверждён provider spec/Q&A, а host unit — canonical Space Payments contract.

### `WebhookPayload`

Обязательные поля: `event`, `payout_id`, `status`. `event` enum имеет значения
`payout.completed`, `payout.failed`, `payout.processing`, `payout.cancelled`;
`status` повторяет пять payout statuses. Optional `external_id`,
`completed_at`, `error`.

### `PayoutError` и `ErrorResponse`

`PayoutError` содержит `code` и `message`; codes include `validation_error`,
`insufficient_balance`, `recipient_not_found`, `bank_unavailable`,
`amount_limit_exceeded`, `rate_limit_exceeded`, `internal_error`. `ErrorResponse`
wraps it under `error`.

### Inline balance response

`balance` и `hold` — integers; descriptions говорят, что balance указан в
kopecks, а hold — замороженная сумма. `currency` — string, example `RUB`.

## Ground truth response status и errors

| Operation | Status | Evidence |
|---|---:|---|
| create | 201 | payout created; `PayoutResponse` |
| create | 400 | `BadRequest` |
| create | 401 | invalid API key / `Unauthorized` |
| create | 402 | insufficient provider balance |
| create | 409 | duplicate idempotency key; response schema is `PayoutResponse` |
| create | 422 | validation error, example mentions minimum kopecks |
| create | 429 | `RateLimited`; `Retry-After` integer seconds |
| create | 500 | `InternalError` |
| status | 200 | payout status |
| status | 401 | unauthorized |
| status | 404 | payout not found |
| cancel | 200 | payout cancelled |
| cancel | 409 | invalid current status |
| webhook | 200 | `{received: true}` example |
| balance | 200 | inline balance object |

Spec не помечает 402 или 500 как retryable в machine-readable field; поэтому
retry policy — это semantic policy, а не прямой fact. Для 429 есть наиболее
сильное retry evidence через `Retry-After`, но bounded retry всё равно остаётся
product rule.

## Структура webhook/callback

- Обычный path `/webhooks/payout` присутствует.
- В baseline нет OpenAPI `callbacks` object.
- В baseline нет top-level `webhooks` object OpenAPI 3.1.
- HMAC algorithm присутствует только в parameter description, а не отдельным
  schema field.
- Safe handler должен проверять raw request bytes до JSON parsing или
  reserialization.

## References и extras

Все baseline schema/response/parameter references — внутренние
`#/components/...` references. В source нет внешних `$ref`.

`getBalance` — реальный provider endpoint, но для него нет прямого метода в
required four-method `Provider::BaseService` contract. По умолчанию он относится
к `extra_operations`, сохраняется и является non-blocking. Он может стать
canonical operation только если выбранный host profile явно объявляет balance
binding. `cancelPayout` аналогично остаётся extra, если profile явно не
предоставляет cancel action.

## Реестр fact и semantic inference

| Topic | OpenAPI fact | Required inference / policy |
|---|---|---|
| create role | POST `/payouts`, payout text, `createPayout` | bind to canonical create payout |
| status role | GET `/payouts/{payout_id}`, `getPayoutStatus` | bind to `fetch_status` |
| amount input | provider integer, explicit request description in kopecks | host `operation.amount` is major RUB; request multiply by 100, response divide by 100; keep evidence separate |
| response amount unit | integer/example only | inherit only with provenance; otherwise review |
| conditional recipient | required fields in descriptions | bounded conditional analyzer; not equivalent to JSON Schema oneOf |
| final statuses | provider enum is explicit | map exact reference values; aliases require review |
| 429 retry | Retry-After integer exists | bounded retry/backoff policy; not infinite retry |
| 402/500 retry | descriptions/statuses only | review policy; no automatic financial assumption |
| 409 create | duplicate idempotency description + PayoutResponse | treat as business/idempotency conflict, not generic retry |
| webhook auth | security empty + HMAC header description | skip API-key auth but verify signature if algorithm explicit |
| extra endpoint | `getBalance` (and `cancelPayout` unless profile declares cancel) is documented | preserve as extra operation; `/balance` is non-blocking; no fake BaseService mapping |
