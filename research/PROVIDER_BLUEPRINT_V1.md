# Provider Blueprint v1

Дата: 2026-09-03

Blueprint — единственный вход генератора. Analyzer-ы не пишут Ruby напрямую;
они создают candidates и evidence, а review/decision gate выпускает
resolved Blueprint. Невыбранные endpoints не исчезают.

## Минимальная schema

```yaml
schema_version: 1
source:
  spec_fingerprint: sha256:...
  fingerprint_inputs:
    root_document: provider_api.yaml
    resolved_local_ref_closure: []
    resolver_policy_version: 1
  input_files: []
  parser_version: 0.1.0
provider:
  name: string
  slug: string
  environment: sandbox|production|mixed
servers: []
base_service_profile:
  name: string
  version: string
  required_methods: []
  request_method_semantics: logical_host_action|http_method|unknown
auth:
  schemes: []
  selected: null
operations: []
endpoints: []
field_mappings: []
money:
  amount_field: null
  host_unit: UNKNOWN
  provider_unit: UNKNOWN
  request_conversion: unresolved
  response_conversion: unresolved
statuses: []
errors: []
idempotency:
  header: null
  spec_required: unknown
  adapter_policy:
    send_header: if_available|always|never|unresolved
    provenance: ADAPTER_POLICY
  retry_policy: unresolved
webhook:
  endpoint: null
  signature: unresolved
  raw_body_required: unknown
conditionals: []
extra_operations: []
decisions: []
warnings: []
unknowns: []
```

## Определения полей

`endpoint` хранит HTTP facts: `method`, `path`, `operation_id`, request и
response schemas, parameters, security и source locations. `operation` — это
canonical projection (`create`, `status`, `cancel`, `callback` или другое
profile-defined action), указывающая на endpoint. Один endpoint нельзя назначить
двум canonical operations без explicit review item.

Each `field_mapping` has:

```yaml
canonical_path: operation.amount
provider_path: request.amount
direction: request|response|callback
transform: identity|minor_to_major|major_to_minor|custom_unresolved
required: true|false|unknown
evidence:
  source: SPEC_FACT|CASE_DEFAULT|BUILTIN_RULE|HUMAN_RULE|PROVIDER_OVERRIDE|HEURISTIC
  locations: []
  excerpt: null
decision: ACCEPT|REVIEW_REQUIRED|UNKNOWN
```

`money.host` и `money.provider` — отдельные evidence-bearing records.
Host/canonical amount не выводится из representation provider-а. Поэтому
request mapping может быть `major_to_minor` с factor `100`, а response mapping —
обратным. `idempotency.spec_required` — OpenAPI fact;
`idempotency.adapter_policy` — product/adapter choice и никогда не должен быть
помечен как `SPEC_FACT`.

`statuses` сохраняют `provider_value`, `canonical_value`, terminality, HTTP
context, evidence и decision. `errors` сохраняют provider code/message fields
и explicit mapping в canonical failure categories. `conditionals` — boolean
branch rules с machine-readable predicate только после confirmation; prose
candidates остаются unresolved.

## Граница BaseServiceProfile

Profile — это contract input, а не guessed implementation detail. Для v1 нужно
как минимум:

```yaml
base_service_profile:
  required_methods:
    - check_conditions
    - create_request
    - process_callback
    - fetch_status
  request_method_semantics: logical_host_action
  canonical_operations: [create, status, cancel, callback]
  success_failure_hooks: declared_by_host
```

Production `BaseService` отсутствует в предоставленном repository. Test-only
stub может реализовать этот profile для fixtures, но generated code не должен
заявлять compatibility, пока не предоставлен реальный profile/host contract.

## Проекция NovaPay case (иллюстративный resolved Blueprint)

Этот sample различает YAML facts, target-host facts и organizer-confirmed case
defaults. Значения `CASE_DEFAULT` и `ADAPTER_POLICY` намеренно показаны явно, а
не представлены как OpenAPI facts.

```yaml
schema_version: 1
source:
  spec_fingerprint: sha256:<computed-over-root-and-resolved-local-ref-closure>
  root_document_sha256: 415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551
  fingerprint_inputs:
    root_document: provider_api.yaml
    resolved_local_ref_closure:
      - '#/components/parameters/IdempotencyKey'
      - '#/components/schemas/CreatePayoutRequest'
      - '#/components/schemas/Recipient'
      - '#/components/schemas/PayoutResponse'
      - '#/components/schemas/WebhookPayload'
      - '#/components/schemas/PayoutError'
      - '#/components/schemas/ErrorResponse'
      - '#/components/responses/BadRequest'
      - '#/components/responses/Unauthorized'
      - '#/components/responses/RateLimited'
      - '#/components/responses/InternalError'
    resolver_policy_version: 1
  input_files: [provider_api.yaml, organizer_case_qa]
provider:
  name: NovaPay
  slug: novapay
  environment: mixed
servers:
  - url: https://api.sandbox.novapay.example/v1
    environment: sandbox
  - url: https://api.novapay.example/v1
    environment: production
base_service_profile:
  name: space_payments_v1
  version: 1
  required_methods: [check_conditions, create_request, process_callback, fetch_status]
  request_method_semantics: logical_action
  callback_actions:
    approved: approve_operation
    rejected: reject_operation
    in_progress: null
auth:
  schemes:
    - name: ApiKeyAuth
      type: apiKey
      in: header
      name: X-API-Key
      evidence_source: SPEC_FACT
  selected: ApiKeyAuth
operations:
  - canonical: create_request
    operation_id: createPayout
    endpoint: POST /payouts
    decision: ACCEPT
  - canonical: fetch_status
    operation_id: getPayoutStatus
    endpoint: GET /payouts/{payout_id}
    decision: ACCEPT
  - canonical: process_callback
    operation_id: payoutWebhook
    endpoint: POST /webhooks/payout
    decision: ACCEPT
extra_operations:
  - operation_id: cancelPayout
    method: POST
    path: /payouts/{payout_id}/cancel
    kind: EXTRA_OPERATION
    preserved: true
    blocking: false
    canonical_binding: none_unless_profile_declares_cancel
  - operation_id: getBalance
    method: GET
    path: /balance
    kind: EXTRA_OPERATION
    preserved: true
    blocking: false
    canonical_binding: none_unless_profile_declares_balance
money:
  host:
    field: operation.amount
    currency: RUB
    unit: major
    representation: major
    source: BASE_SERVICE_PROFILE
    evidence_source: BASE_SERVICE_PROFILE
    evidence:
      - source: BASE_SERVICE_PROFILE
        location: profile#/canonical_amount
  provider:
    field: request.amount
    currency: RUB
    unit: minor
    subunit: kopecks
    representation: minor
    unit_name: kopecks
    scale: 100
    scale_source: CASE_DEFAULT
    source: [SPEC_DESCRIPTION, CASE_DEFAULT]
    evidence_sources: [SPEC_DESCRIPTION, CASE_DEFAULT]
  request_conversion:
    direction: major_to_minor
    operation: multiply
    factor: 100
    factor_decimal: '100'
    scale: 100
  response_conversion:
    direction: minor_to_major
    operation: divide
    factor: 0.01
    factor_decimal: '0.01'
    scale: 100
  decision: ACCEPT
conditionals:
  - predicate: recipient.type == sbp
    required: [recipient.bank_code]
    evidence_sources: [SPEC_DESCRIPTION]
    decision: ACCEPT
  - predicate: recipient.type == card
    required: [recipient.card_number]
    evidence_sources: [SPEC_DESCRIPTION, CASE_DEFAULT]
    decision: ACCEPT
webhook:
  endpoint: POST /webhooks/payout
  signature:
    algorithm: HMAC-SHA256
    header: X-NovaPay-Signature
    algorithm_evidence_source: SPEC_DESCRIPTION
    input: raw_body
    input_evidence_source: CASE_DEFAULT
    encoding: hex
    encoding_evidence_source: CASE_DEFAULT
    header_evidence_source: SPEC_DESCRIPTION
    decision: ACCEPT
  raw_body_required: true
  decision: ACCEPT
idempotency:
  header: Idempotency-Key
  spec_required: false
  spec_evidence_source: SPEC_FACT
  adapter_policy:
    send_header: always
    provenance: ADAPTER_POLICY
  retry_policy:
    name: preserve_same_key
    provenance: ADAPTER_POLICY
statuses:
  - provider_value: pending
    canonical_value: in_progress
    evidence_source: CASE_DEFAULT
  - provider_value: processing
    canonical_value: in_progress
    evidence_source: CASE_DEFAULT
  - provider_value: completed
    canonical_value: approved
    evidence_source: CASE_DEFAULT
  - provider_value: failed
    canonical_value: rejected
    evidence_source: CASE_DEFAULT
  - provider_value: cancelled
    canonical_value: rejected
    evidence_source: CASE_DEFAULT
decisions: []
warnings: []
unknowns: []
```

Sample не утверждает, что каждое значение можно восстановить из YAML. В real
run decision log указывает на Q&A artifact и требует acceptance при
использовании `CASE_DEFAULT`. Provider без этих defaults получает
`REVIEW_REQUIRED`/`UNKNOWN`, а не копию этого sample.

## Правила projection

- `SPEC_FACT` structural mappings могут быть приняты, если они однозначны.
- Money conversion, status semantics, callback signature semantics и logical
  host actions требуют explicit evidence или scoped confirmed rule.
- Каждый extra endpoint сохраняется в Blueprint и показывается в readiness
  report.
- Generator использует только validated resolved Blueprint; candidates,
  conflicts и unknowns остаются в review manifest.
