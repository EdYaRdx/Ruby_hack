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

Total decisions: 7 cases

ACCEPT: 0

REVIEW_REQUIRED: 7

UNKNOWN: 0

BLOCKING: 17 decision entries across the lane

Automatic accept rate: 0.0%; safe decision coverage
100.0%. This is an honest result of the official spec-only input: status
business outcomes and part of webhook semantics are not fully documented.

Critical false ACCEPTs: 0

The machine-readable result is [`spec_only_novapay_report.json`](spec_only_novapay_report.json).

## THIRD PROVIDER

Name: HeliosPay

Ground truth authored before run: YES

Spec-only decision: `REVIEW_REQUIRED` (13 decisions: 11 accepted, 2 review,
0 blocking)

Resolved generation: PASS

Runtime verification: PASS

Resolved behavioral vectors: 4/4

## BENCHMARK

Reference mutation: 37/37

Reference metrics: automatic accept rate 48.6%; safe decision coverage 100.0%;
semantic accept accuracy 100.0%; critical false ACCEPTs 0.

Spec-only mutation: 7 cases

Spec-only automation coverage: 0.0% automatic accept rate; 100.0% safe decision
coverage; critical false ACCEPTs 0.

Do not combine these metrics.

## AURORA

Spec-only: REVIEW_REQUIRED

Resolved: ACCEPT

Semantic: 100.0%

Behavioral: 4/4

## PREVIEW

NovaPay literals in generic PreviewService: 0 in the generic Blueprint/fixture
preview logic (NovaPay remains only in the explicit demo registry).

NovaPay: PASS

Aurora: PASS

Third provider: PASS (HeliosPay)

## REGRESSION

RSpec: 72 examples, 0 failures after the final regression run.

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
