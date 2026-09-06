# Integration Readiness

## Provider

- Provider: `NovaPay`
- Spec fingerprint: `sha256:2b6ad1db111691c80f3b098d76d69896fc88c7b0859f9a17af725325dbbbda77`
- Host profile: `space_payments_v1 v1`

## Semantic coverage

- Operations found: 5
- Canonical operations: create_request, fetch_status, process_callback
- Extra operations preserved: 2
- Auth: `ApiKeyAuth`
- Money: `major -> minor`
- Status mappings: 5
- Field mappings: 7
- Webhook mode: ``
- Idempotency spec required: `false`

## Human effort

- Total semantic decisions: 14
- Automatically resolved decisions: 14
- Questions requiring review: 0
- Human decisions supplied: 0
- Blocking unknowns: 0
- Unsupported critical features: 0

## Generation

- `generation_ready`: `true`
- `generated`: `true`
- Verification: `PASS`
- Overall readiness: `READY`

## Required runtime configuration

- NOVAPAY_BASE_URL (optional sandbox default)
- provider API credential passed to generated service

## Known limitations

- Production Provider::BaseService and its client/result classes are not included in this checkout
- Webhook secret and API credentials are runtime configuration, never persisted in Review overrides
