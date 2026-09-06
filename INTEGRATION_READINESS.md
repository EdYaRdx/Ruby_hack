# Integration Readiness

This is the readiness report generated from the current NovaPay pipeline and
verification result. It is a local release artifact, not a claim that a real
Space Payments production runtime is present in this checkout.

## Provider

- Provider: `NovaPay`
- Spec fingerprint: `sha256:2b6ad1db111691c80f3b098d76d69896fc88c7b0859f9a17af725325dbbbda77`
- Root document SHA-256: `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551`
- Host profile: `space_payments_v1 v1`

## Semantic coverage

- Operations found: `5`
- Canonical operations: `create_request`, `fetch_status`, `process_callback`
- Extra operations preserved: `2` (`cancelPayout`, `getBalance`)
- Auth: `ApiKeyAuth`, header `X-API-Key`
- Money: host `major RUB` -> provider `minor kopecks`, scale `100`
- Conversion: request `multiply x100`; response `divide by 100`
- Status mappings: `5`
- Field mappings: `7`
- Webhook: `POST /webhooks/payout`, HMAC-SHA256, `X-NovaPay-Signature`, raw body, hex
- Idempotency spec required: `false`
- Idempotency adapter policy: `if_available` (`ADAPTER_POLICY`)

## Human effort and safety

- Total semantic decisions: `14`
- Automatically resolved: `14`
- Questions requiring review: `0`
- Human decisions supplied: `0`
- Blocking unknowns: `0`
- Unsupported critical features: `0`

## Generation

- `generation_ready`: `true`
- `generated`: `true`
- Verification: `PASS`
- Overall local readiness: `READY`

## Required runtime configuration

- `NOVAPAY_BASE_URL` or the provider sandbox default
- Provider API credential supplied to the generated service
- Webhook secret supplied at runtime

## Known limitations

- Production `Provider::BaseService` and its client/result classes are not
  included in this checkout; local verification uses the repository harness.
- The successful GitHub Actions matrix run for the final production hotfix
  [34049724064](https://github.com/EdYaRdx/Ruby_hack/actions/runs/34049724064)
  verified Windows/Linux and Ruby 3.3/4.0; the local checkout execution itself
  remains Windows-only.
- Provider credentials and webhook secrets are runtime inputs and are never
  persisted in Review overrides.
