# GOAL 6.1 FINAL RESULT

## 1. GOAL 6.0 input

P0: webhook event/status contradiction could approve a failed payload.

P1: unproven production `BaseService` boundary, query fallback loss, local-ref
symlink escape, unbounded hostile input, runtime regex/class/server URL risks.

## 2. Frozen corpus

- Cases: 12.
- Shared host profile: 12/12 `profiles/space_payments_v1.yml`.
- Freeze commit: `7257a89 test: freeze black-box provider corpus v1`.
- Ground truth changed after freeze: NO.
- Local `$ref` inputs and hashes: `research/black_box_v1/MANIFEST.json`.

## 3. Baseline

- Safe semantic accuracy: 58.3% (7/12).
- Decision automation: 0.0%.
- REVIEW_REQUIRED: 33.3%; UNKNOWN: 66.7%.
- Fully auto-ready: 0.0%.
- Critical false ACCEPTs: 0.
- Unsafe generation attempts: 0.
- Compiler crashes: 0.

## 4. Confirmed bugs and fixes

| ID | Symptom | Test | Fix |
|---|---|---|---|
| R1 | Inline/external status evidence became UNKNOWN | frozen cases 02, 03, 12 | scan operation schemas as well as components |
| R2 | Required custom parameters were not preserved | frozen case 09 | `unsupported_features` diagnostics with blocking generation impact |
| R3 | Contradictory signed webhook could approve | runtime hardening spec | fail closed before callback action |
| R4 | Query auth disappeared in GET/POST fallback | local HTTP/fallback tests | append canonical query to fallback URL |
| R5 | Object/malformed responses could crash or misclassify | runtime hardening spec | response normalization and explicit failure envelope |
| R6 | HTTP error without code selected first known code | 429 runtime vector | exact-code-only mapping; preserve HTTP category and Retry-After |
| R7 | Hostile refs/regex/class/URL were unsafe | hostile OpenAPI suites | canonical root checks, limits, validation and rejection |

## 5. BaseService boundary

Guaranteed by the official case: conceptual required methods and helper names.

Profile assumptions: `call_super`, declared failure argument list, validation
codes/status, callback actions.

Test-harness assumptions: Hash result/client stubs. Remaining unknowns: the
real production constructor, HTTP client method signatures and failure/result
objects are not present in this checkout. The project does not claim production
compatibility from the harness alone.

## 6. Real HTTP

| Vector | Result |
|---|---|
| POST create | PASS |
| GET fetch status | PASS |
| Query API key | PASS |
| Header API key | PASS |
| JSON request/response | PASS |
| 429 + Retry-After | PASS |
| 204 without body | PASS |

The path is generated adapter → localhost WEBrick → Net::HTTP → generated
response mapping; no external provider call is made.

## 7. Runtime edge cases

Provider error without code, known error, malformed response, unknown status,
missing provider id, missing/invalid webhook input, unresolved callback action,
polling-only callback and event/status contradiction are covered and pass.
Idempotency claims are honest: fallback-generated keys are process-local, not
durable across restart.

## 8. Hostile OpenAPI

26 adversarial inputs completed with explicit safe outcomes; one symlink test is
pending only because this Windows environment cannot create symlinks without
additional privilege. Unexpected exceptions: 0. Unsafe generation attempts: 0.
See [`docs/SUPPORT_MATRIX.md`](../docs/SUPPORT_MATRIX.md).

## 9. Final frozen corpus

- Safe semantic accuracy: 100.0% (12/12).
- Critical false ACCEPTs: 0.
- Unsafe generation attempts: 0.
- Compiler crashes: 0.
- Generation-ready cases: 0/12 by design; corpus targets ambiguity/refusal.
- Runtime-ready corpus vectors: separate local HTTP suite, all pass.

## 10. Regression

- RSpec: 98 examples, 0 failures, 1 environment-pending symlink example.
- Reference benchmark: 37/37; semantic areas 100%; generation 18/18.
- NovaPay spec-only: 7/7.
- Aurora: 3/3; behavioral vectors 4/4.
- HeliosPay: 2/2; behavioral vectors 4/4.
- Docs/examples idempotence: PASS.
- Ruby syntax: 37/37.
- Ruby share: 89.5% production.
- `git diff --check`: PASS; working tree clean.

## 11. Verdict

- HACKATHON REGRESSION: NONE
- HOST CONTRACT HARDENED: YES, with production contract evidence still required
- REAL GENERATED HTTP PROVEN: YES
- UNKNOWN OPENAPI HANDLED SAFELY: YES
- FROZEN CORPUS INTACT: YES
- P0 REMAINING: NONE in the audited runtime scope
- READY FOR GOAL 6.2: YES

