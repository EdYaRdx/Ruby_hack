# GOAL 5 RESULT

## EXECUTIVE SUMMARY

Goal 5 hardens the existing Facts IR -> Review Manifest -> Provider Blueprint ->
deterministic generator pipeline without changing its architecture. Generic Web
uploads and explicit CLI `--spec` runs no longer inherit NovaPay defaults.
OpenAPI success codes, error categories, Retry-After, fixture provenance and
profile-driven BaseService behavior now reach generated runtime.

Remaining high-risk issue: a provider whose OpenAPI omits business status
meaning or webhook outcome semantics still requires review. The compiler does
not turn that absence into an ACCEPT decision.

## WEB DEFAULTS

SHA auto-default removed: YES

Reference demo explicit: YES

Generic upload uses empty defaults: YES

## CLI DEFAULTS

Custom `--spec` without defaults: EMPTY

NovaPay leakage: NO

`inspect` reports the spec, host profile and provider defaults source.

## CASEDEFAULTS

NovaPay values before: provider unit/field mappings and fixture semantics were
partly duplicated in case defaults.

NovaPay values after: only named-case scale, webhook encoding, status outcomes
and deterministic demo examples remain.

Moved to spec extraction: operation mapping, request/response fields, provider
minor unit from the amount description, auth, optional idempotency header,
success response codes, error HTTP categories, nested money where documented,
and local reference resolution.

Remaining defaults: named-case scale 100 where the spec says “kopecks” but does
not declare a numeric scale; status/business outcome mappings; webhook demo
encoding fallback; demo examples.

Why remaining defaults are necessary: they represent external provider/business
knowledge or demo data that is absent from the OpenAPI document. They are
explicitly loaded and never inferred from filename or fingerprint.

## SUCCESS RESPONSES

Hardcoded 200/201 removed: YES

202 test: PASS

204 handling: PASS

## ERROR RUNTIME

ErrorAnalyzer projected to runtime: YES

400: `validation_error`

401: `unauthorized`

402: `insufficient_balance`

409: `conflict`

422: `validation_error`

429: `rate_limit_exceeded`

500: `internal_error`

Retry-After: PASS; unknown provider codes and raw error details are preserved.

## BASESERVICE

OrganizerContractHarness: YES (test-only, based on the provided contract
pattern)

check_conditions super: PASS

failure contract: PASS (`status`, `code`, `message`)

Generated NovaPay compatibility: PASS

## FIXTURES

Primary source: SPEC with CaseDefaults fallback

OpenAPI example support: PASS

Schema synthesis: PASS (including defaults, enum and deterministic samples)

Deterministic: PASS

## GENERATED DOCS

Error mapping quality: PASS; integration documentation uses resolved
HTTP/category mappings and does not repeat the complete provider enum for every
status.

## SPEC-ONLY NOVAPAY

Official baseline (one run of `fixtures/novapay_provider_api.yaml` with no
provider defaults):

- Total decisions: 14
- Accepted: 10
- REVIEW_REQUIRED: 4
- Blocking entries: 3
- Decision-level automation: 10/14 = 71.4%
- Review rate: 4/14 = 28.6%
- Fully auto-ready: 0/1 = 0.0%
- Critical false ACCEPTs: 0
- Unsafe generation attempts: 0

The official specification supports automatic facts such as operation paths,
request/response fields and provider auth where explicitly documented. Status
business outcomes and part of webhook semantics remain review concerns. The
spec-only run does not generate an adapter.

Mutation lane (seven spec-only cases):

- Total decisions: 98
- Accepted: 74
- REVIEW_REQUIRED: 24
- Blocking entries: 17
- Decision-level automation: 74/98 = 75.5%
- Review rate: 24/98 = 24.5%
- Fully auto-ready: 0/7 = 0.0%
- Critical false ACCEPTs: 0
- Unsafe generation attempts: 0

The machine-readable result is [`spec_only_novapay_report.json`](spec_only_novapay_report.json).

## THIRD PROVIDER

Name: HeliosPay

Ground truth authored before run: YES

Spec-only decision: `REVIEW_REQUIRED` (13 decisions: 11 accepted, 2 review,
0 blocking); decision automation 11/13 = 84.6%; fully auto-ready 0/1.

Resolved generation: PASS

Resolved decision automation: 13/13 = 100.0%; fully auto-ready 1/1.

Runtime verification: PASS

Resolved behavioral vectors: 4/4

## BENCHMARK

Reference mutation: 37/37 adversarial mutations of one reference provider
domain, not 37 providers.

Reference metrics: decision-only legacy accept rate 48.6%; safe decision
coverage 100.0%; semantic ACCEPT accuracy 100.0%; critical false ACCEPTs 0.

Spec-only mutation: 7 cases

Spec-only decision automation is reported separately above. It must not be
confused with full-spec auto-ready status.

Do not combine these metrics.

## AURORA

Spec-only: REVIEW_REQUIRED (14 decisions: 12 accepted, 2 review, 1 blocking;
decision automation 85.7%; fully auto-ready 0/1)

Resolved: ACCEPT (14/14 accepted; fully auto-ready 1/1)

Semantic: 100.0%

Behavioral: 4/4

## PREVIEW

NovaPay literals in generic PreviewService: 0 in the generic Blueprint/fixture
preview logic (NovaPay remains only in the explicit demo registry).

NovaPay: PASS

Aurora: PASS

Third provider: PASS (HeliosPay)

## REGRESSION

RSpec: 77 examples, 0 failures after the final regression run.

Web smoke: PASS

CLI verify: PASS

Official SHA: `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551`

update_docs idempotent: PASS (repeat run produced identical canonical artifacts)

update_examples idempotent: PASS (repeat run produced identical canonical artifacts)

git diff --check: PASS

## COMPLIANCE

Ruby majority: PASS

OSS dependencies: PASS

Neural runtime: NONE

Proprietary core dependency: NONE

## BACKEND ARCHITECTURE

Facts IR preserved: YES

Manifest preserved: YES

Blueprint source of truth: YES

Fail closed preserved: YES

No Web UI redesign or compiler architecture rewrite was introduced.

## KNOWN LIMITATIONS

- Spec-only NovaPay intentionally stops when status/business outcome mappings or
  webhook outcome/encoding semantics are absent.
- `CaseDefaults` still carries named-case business knowledge; it is explicit and
  scoped, not a generic provider inference mechanism.
- Generated adapters are projections of the supplied host profile and should
  be checked against the real production BaseService implementation.

## FINAL ASSESSMENT

SPEC-ONLY AUTOMATION READY: NO — safe and measurable, but the official
spec-only lane correctly requires review for missing business semantics.

GENERATOR CORRECTNESS READY: YES

UNIVERSALITY EVIDENCE READY: YES

CHECKPOINT READY: YES

SUBMISSION READY: YES
