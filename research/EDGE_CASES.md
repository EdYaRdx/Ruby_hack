# Граничные случаи и safety policy

## Словарь decisions

| Decision | Meaning | Codegen |
|---|---|---|
| `ACCEPT` | evidence достаточно, конфликтов нет, margin достаточный | blueprint может идти в generator |
| `REVIEW_REQUIRED` | есть кандидат, но критичное решение нельзя принять автоматически | blueprint сохраняется, generation блокируется при blocking issue; текущий CLI не имеет `--allow-review` |
| `UNKNOWN` | конфликт, невозможная ссылка или нет надёжного кандидата | codegen блокируется, причина обязательна |

Score — это объяснимый вес evidence, не вероятность. Каждое решение хранит:
`candidate`, `evidence_sources[]`, `score`, `top2_margin`, `conflicts[]`,
`decision`, `warnings[]`.

## Parser и references

| Случай | Ожидаемое поведение |
|---|---|
| OpenAPI 3.0.x | принять и нормализовать |
| OpenAPI 3.1.x | принять только если выбранный parser/validator подтвердил fixture; иначе понятный unsupported report |
| internal `#/components/...` `$ref` | resolve, сохранить исходный pointer |
| local external `$ref` внутри allowlisted root | resolve, сохранить absolute path и provenance |
| external `$ref` вне root или URL без явного opt-in | `UNKNOWN`; не скачивать молча |
| unresolved `$ref` | `UNKNOWN`; не генерировать частичный Ruby |
| циклический ref | parser должен сохранить graph; validator/analyzer не должен зациклиться |
| invalid OpenAPI | validation error с JSON pointer и остановка до analyzer |

## Discovery operations

- Сначала exact signals: `operationId`, path, HTTP method, tags, request/response
  schema shape, response codes.
- `POST /payouts` + payout wording может дать `create_payout` даже без
  `operationId`.
- `/transfers`, `/withdrawals`, `initiateTransfer`, `makeWithdrawal` — aliases
  для candidate, но не автоматический payout ACCEPT.
- `POST /transactions` без differentiating evidence — `UNKNOWN`.
- `cancel` и `balance` остаются в `extra_operations`; они документированы, но не
  должны молча принудительно назначаться `create_request`/`fetch_status`.
- Новые operations, например `/limits`, сохраняются в diagnostics и docs с
  `decision: EXTRA_UNMAPPED`.

## MoneyAnalyzer

1. Предпочитать explicit unit words в operation/property description, schema
   extension или example вместе с explicit currency/unit evidence.
2. Один `integer` не доказывает minor units; один `RUB` не доказывает kopecks.
3. Explicit minor units -> no conversion; explicit major units -> deterministic
   x100 для RUB-like currencies только если это предусматривает provider rule.
4. `sum`, `total`, `money.value` — candidate aliases -> `REVIEW_REQUIRED`.
5. Currency-specific behavior должен быть named rule. Иначе money
   transformation остаётся `unknown`, без multiply/divide.

## StatusMapper

Canonical base statuses — `in_progress`, `approved`, `rejected`. Exact provider
enum values `pending`, `processing`, `completed`, `failed`, `cancelled`
сопоставляются по reference case. `settled`, `success`, `declined`, `voided` —
только review-only aliases, если provider-specific explicit description или
event relation не устанавливает их terminal meaning. Unknown terminal status —
`UNKNOWN`; его нельзя считать approved или rejected.

## Idempotency и retry safety

- Определять header по `in: header`, а не по hardcoded name.
- Считать semantics explicit только когда name/description говорит об
  idempotency или duplicate prevention.
- При переименовании с сохранённым description обновить header name и дать
  `ACCEPT`.
- Отсутствующий idempotency означает отсутствие automatic replay/retry;
  для create operation нужен `REVIEW_REQUIRED`, поскольку отсутствие не
  доказывает безопасность retries.
- Дубликат `409` — business response, а не generic retry signal.
- `429` retryable только при provider policy и `Retry-After`; header value нужно
  сохранять в diagnostics.

## ErrorAnalyzer

| HTTP | Reference evidence | Initial category | Default action |
|---:|---|---|---|
| 400 | BadRequest | request/business validation | reject |
| 401 | Unauthorized | auth | alert/block; no retry loop |
| 402 | insufficient_balance | provider balance | review/retry policy, never blind immediate retry |
| 404 | not_found | lookup/business | fail lookup |
| 409 | duplicate or invalid status | idempotency/business conflict | inspect body; no generic retry |
| 422 | validation_error | request validation | reject |
| 429 | Retry-After + rate_limit_exceeded | rate limit | bounded retry with header/backoff |
| 500 | internal_error | provider internal | bounded retry + alert |

Одного HTTP code недостаточно, если body schemas или descriptions конфликтуют.
Error mapping хранит и status, и provider code.

## WebhookAnalyzer

- Обнаруживать ordinary POST paths, OpenAPI callback expressions и top-level
  `webhooks` OpenAPI 3.1; всё нормализовать в один IR node.
- `security: []` у webhook означает отсутствие API-key auth requirement. Это не
  отключает signature verification.
- Signature header и algorithm — отдельные facts. `X-NovaPay-Signature` вместе
  с explicit HMAC-SHA256 -> `ACCEPT`; header без algorithm -> `REVIEW_REQUIRED`.
- Для verification нужны raw request bytes. JSON reserialization не является
  безопасной заменой.
- При отсутствии webhook генерировать polling-only output с warning; не
  придумывать callback URL.

## AuthAnalyzer

В MVP поддерживать только explicit API key header, API key query и Bearer schemes.
Generated config должен использовать declared name/location. Unsupported schemes
или несколько конфликтующих security alternatives ->
`REVIEW_REQUIRED`/`UNKNOWN`. Для query API keys в docs выдаётся leakage warning.

## ConditionalFieldAnalyzer

Реализовать только:

- schema `required`;
- `oneOf`/`anyOf`/discriminator when validator supports it;
- bounded description patterns such as `required when type=sbp` and
  `обязателен при type=card`.

Free-form natural language, nested contradictions и undocumented conditional
rules становятся warnings/review. Для NovaPay `bank_code` и `card_number` —
conditional по description, а не encoded as `oneOf`; generated guide должен
явно это указать.

## Minimal Provider Blueprint shape

```json
{
  "schema_version": 1,
  "provider": {"name": "NovaPay", "slug": "novapay", "version": "1.0.0"},
  "servers": [{"url": "https://api.sandbox.novapay.example/v1", "environment": "sandbox"}],
  "auth": {"kind": "api_key", "location": "header", "name": "X-API-Key"},
  "canonical_operations": {
    "create": {"endpoint_ref": "...", "decision": "ACCEPT"},
    "status": {"endpoint_ref": "...", "decision": "ACCEPT"},
    "callback": {"endpoint_ref": "...", "decision": "ACCEPT"}
  },
  "provider_endpoints": [],
  "field_mappings": [],
  "money_transformation": {
    "host": {"unit": "major", "currency": "RUB", "evidence": "BASE_SERVICE_PROFILE"},
    "provider": {"unit": "minor", "subunit": "kopecks", "evidence": ["SPEC_DESCRIPTION", "CASE_DEFAULT"]},
    "request": {"operation": "multiply", "factor": 100, "scale": 100},
    "response": {"operation": "divide", "factor": 0.01, "scale": 100}
  },
  "status_mappings": [],
  "error_mappings": [],
  "idempotency_policy": {
    "spec_required": false,
    "adapter_policy": {"send_header": "always", "provenance": "ADAPTER_POLICY"}
  },
  "webhook_policy": {},
  "conditional_fields": [],
  "extra_operations": [
    {"operation_id": "cancelPayout", "method": "POST", "path": "/payouts/{payout_id}/cancel", "blocking": false},
    {"operation_id": "getBalance", "method": "GET", "path": "/balance", "blocking": false}
  ],
  "evidence": [],
  "decision": "ACCEPT",
  "warnings": [],
  "unknowns": []
}
```

Example иллюстративен; actual Ruby object должен сохранять JSON pointers,
headers, schemas и source excerpts, не встраивая free-form guesses.
