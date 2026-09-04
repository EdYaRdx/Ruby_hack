# Исправления ground truth NovaPay

Дата проверки: 2026-09-04

Проверены напрямую:

- official `provider_api.yaml` fixture (OpenAPI 3.0.3,
  root SHA-256 `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551`);
- organizer Q&A supplied with the task;
- иллюстративные Blueprint/ground-truth блоки в `research/`.

## Исправления

| # | Corrected ground truth | Evidence | Change made |
|---:|---|---|---|
| 1 | Space `operation.amount` is major RUB; provider `request.amount` is minor RUB/kopecks; request `×100`, response `/100` | YAML `POST /payouts` description/schema; organizer Q&A; current host instruction | Blueprint now has separate `money.host` and `money.provider` evidence plus directional conversions |
| 2 | `Idempotency-Key` is optional in OpenAPI (`required: false`) | YAML `#/components/parameters/IdempotencyKey` | `spec_required: false`; any always-send behavior is `adapter_policy`, provenance `ADAPTER_POLICY` |
| 3 | Status operationId is `getPayoutStatus` | YAML `GET /payouts/{payout_id}` | Corrected Blueprint and ground-truth references |
| 4 | Sandbox URL is `https://api.sandbox.novapay.example/v1` | YAML `servers[0].url` | Corrected every illustrative server value |
| 5 | `/balance` is an `EXTRA_OPERATION` by default, preserved and non-blocking | YAML `GET /balance`; four-method BaseService case contract | Removed it from canonical NovaPay operations; profile may opt in explicitly |
| 6 | Fingerprint covers root plus resolved local-ref closure and resolver policy | YAML contains internal `#/components/...` refs | Blueprint now separates root hash from computed resolved-input fingerprint and lists the closure |
| 7 | All remaining illustrative values were rechecked | YAML + Q&A | Auth, endpoints, conditional fields, statuses, webhook, errors and server metadata are recorded with correct provenance |

## Повторно проверенные значения NovaPay

| Area | Verified value |
|---|---|
| OpenAPI | `3.0.3`; title `NovaPay Payout API`; version `1.0.0` |
| Servers | sandbox `https://api.sandbox.novapay.example/v1`; production `https://api.novapay.example/v1` |
| Endpoints | `POST /payouts`, `GET /payouts/{payout_id}`, `POST /payouts/{payout_id}/cancel`, `POST /webhooks/payout`, `GET /balance` |
| operationIds | `createPayout`, `getPayoutStatus`, `cancelPayout`, `payoutWebhook`, `getBalance` |
| API auth | `ApiKeyAuth`, header `X-API-Key`; webhook has `security: []` |
| Create request | required `amount`, `currency`, `external_id`, `recipient`; amount provider-side integer kopecks |
| Idempotency | header `Idempotency-Key`, UUID, `required: false`; duplicate-prevention description |
| Recipient conditions | `bank_code` required for `type=sbp`; `card_number` required for `type=card`; descriptions/Q&A, not schema `oneOf` |
| Provider statuses | `pending`, `processing`, `completed`, `failed`, `cancelled` |
| Case-default mapping | `pending/processing → in_progress`; `completed → approved`; `failed/cancelled → rejected` |
| Webhook | required `X-NovaPay-Signature`; HMAC-SHA256; Q&A specifies raw body, hex encoding |
| Errors/retry | create 400/401/402/409/422/429/500; status 401/404; cancel 409; `Retry-After` on 429; retry behavior remains policy |
| Extra operation | `/balance` preserved as non-blocking `EXTRA_OPERATION` unless profile explicitly binds balance |

## Влияние на архитектуру

**High-level architecture: без изменений.** Существующие pipeline и boundaries
остаются прежними:

```text
ingest -> facts IR -> analyzers/evidence -> Blueprint -> projections -> verification
```

Corrections затрагивают только ground-truth data contract и один implementation
invariant для input identity:

- money needs two directional mappings and two evidence records;
- idempotency needs separate spec fact and adapter policy fields;
- `/balance` needs the existing extra-operation path;
- fingerprint calculation must run over the resolved reference closure.

Добавленные проверки остаются stages внутри существующей analyzer/evidence
boundary; новый top-level pipeline, UI, runtime service или alternative
architecture не вводится. Поэтому существующая architecture **не redesign**;
исправлены её Blueprint fields, generated projection и implementation notes для
fingerprint.
