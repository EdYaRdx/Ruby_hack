# GOAL 6.10 — final spec-only and compile validation

Date: 2026-09-06

## Baseline before GOAL 6.10

The pre-change checkout was clean at `298abd8`. Existing frozen evidence was
preserved: RSpec `135 examples, 0 failures, 1 pending` (the pending case is
the Windows symlink boundary), reference mutation `37/37`, black-box `12/12`,
Aurora `3/3`, HeliosPay `2/2`, NovaPay spec-only mutation `7/7`, and prior CI
matrix `4/4`.

## Readiness consistency

The stale-artifact bug is fixed: `AnalysisArtifactWriter` now removes old
runtime and readiness files when a later analysis is unresolved. A regression
test covers generate → analyze cleanup.

Resolved NovaPay readiness now reports:

| Measure | Result |
|---|---:|
| Total semantic decisions | 14 |
| Accepted in current Blueprint | 14 |
| Accepted without HUMAN_CONFIRMED | 14 |
| Decisions with SPEC evidence | 14 |
| Decisions with BUILTIN/generic rule evidence | 0 |
| Decisions resolved using CASE_DEFAULT | 3 |
| HUMAN_CONFIRMED | 0 |
| REVIEW_REQUIRED | 0 |
| BLOCKING | 0 |
| Webhook mode | `webhook` |

`automatic_accept_count` remains as a backward-compatible JSON alias, but the
human-facing report no longer calls that outcome count “automatically
resolved” without provenance qualification. Host money evidence remains
`BASE_SERVICE_PROFILE`; provider money evidence remains provider/spec/default
evidence. The OpenAPI optional idempotency requirement remains separate from
the adapter policy.

## Independent spec-only success corpus

`research/spec_only_success_v1/` is a new independent lane with three
materially different synthetic explicit OpenAPI specifications. It uses no
CaseDefaults and no HUMAN_CONFIRMED overrides. Expectations are hand-authored
in `ground_truth.yml`; runtime expectations are hand-authored in
`behavioral_vectors.yml`.

| Measure | Result |
|---|---:|
| Providers | 3 |
| Spec-only ACCEPT | 3/3 |
| Semantic comparison | 3/3 |
| Generation + contract + localhost transport | 3/3 |
| Independent behavioral vectors | 3/3 |
| CaseDefaults used | 0 |
| HUMAN_CONFIRMED overrides | 0 |

The corpus covers query API key with scale 100, Bearer with nested major-unit
money and polling-only callbacks, and header API key with scale 1000 and HMAC
callbacks. The comparator checks operation mappings, money conversion,
authentication, statuses, webhook semantics, fields and runtime behavior.

## Metrics and independent Aurora check

The historical decision-only reference metric remains `automatic_coverage:
100.0%` for the 37-case mutation lane, with decision accuracy `100.0%`. It is
reported only as a legacy comparison; it is not semantic validation.

The independent success corpus reports `spec_only_accept_rate: 100.0%`,
`safe_decision_coverage: 100.0%` (3 passed providers / 3 providers), semantic
acceptance `3/3`, generation `3/3`, and behavioral vectors `3/3`. Its independent
area metrics are: operation, money, status, auth, webhook, idempotency and field
mapping semantic accuracy — all `100.0%`. Critical false ACCEPTs and unsafe
generation attempts are `0`.

Aurora's resolved Blueprint was compared against hand-authored semantics:

| Area | Independent result |
|---|---|
| Operations | `initiateTransfer` POST `/transfers`; `getTransferState` GET `/transfers/{transfer_id}`; callback POST `/notifications` |
| Money | nested `money.value` / `money.currency`; host major USD → provider major USD, scale `1` |
| Auth and idempotency | Bearer `Authorization`; optional `X-Aurora-Request-Token` with adapter-policy provenance |
| Statuses and webhook | queued/settled/declined/voided → in_progress/approved/rejected/rejected; HMAC-SHA256, `X-Aurora-Signature`, raw-body/hex resolution |
| Runtime vectors | hand-authored create request, settled approval, declined rejection and status response vectors passed |
| Extra operations | preserved as non-blocking `EXTRA_OPERATION` entries |

## Compiler changes and architecture impact

One real generic correctness gap was found by the corpus: explicit canonical
status mappings in OpenAPI descriptions were not being read. The analyzer now
accepts only the narrow unambiguous description marker
`provider_value: canonical canonical_value`; ordinary aliases remain review.
This is a semantic evidence fix, not a provider-specific branch.

The one-command `compile` CLI is orchestration over the existing pipeline:
`Pipeline → Blueprint → Generator → Verification → Readiness`. It does not
introduce a second compiler or alter the safety threshold. Architecture impact:
no redesign; one generic analyzer correctness fix, one CLI orchestration entry
point, and benchmark/reporting additions.

## Compile checks

| Scenario | Result |
|---|---|
| A. Resolved NovaPay with explicit defaults | exit `0`, READY, service/fixtures/readiness generated |
| B. NovaPay spec-only without defaults | exit `2`, REVIEW_REQUIRED, no service/fixtures/contract runtime artifacts |
| C. Arbitrary explicit provider without defaults | exit `2`, no implicit NovaPay defaults, no runtime artifacts |

The CLI prints provider, input, decision, provenance breakdown, generated
files, verification and final result.

## Packaging and regression

- gem homepage/source/bug metadata: present;
- license: unchanged/not invented;
- executable flags: `bin/provider_compiler` and `bin/provider_compiler_web`
  are `100755` in git;
- dependencies: unchanged;
- full RSpec after changes: `140 examples, 0 failures, 1 pending`;
- reference mutation: `37/37`, critical false ACCEPTs `0`;
- frozen black-box: `12/12`;
- Aurora: `3/3`;
- HeliosPay: `2/2`;
- spec-only success corpus: `3/3`;
- `git diff --check`: PASS;
- `update_docs`: run twice successfully;
- `update_examples`: run successfully after the final semantic changes;
- `gem build provider_compiler.gemspec`: PASS locally (with the expected missing-license warning);
- the final 4-cell GitHub Actions matrix remains an external post-push check.

## Final verdict

BACKEND BENCHMARK VALIDATED

GO for GOAL 4.
