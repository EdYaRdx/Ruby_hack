# RUBRIC TRACEABILITY V2

Дата: 2026-09-06  
Метод: conservative external audit against the official case document and
observed repository behavior.

## Denominator discrepancy

The official описание.docx directly read for this audit lists:

- Experts: 100 points;
- Technical jury: 100 points;
- Industry criteria: 20 points.

The audit request says section B is /103. No authoritative three-point
addendum was found in the official DOCX or checkout. Therefore:

- scores below use the official published /100 technical denominator;
- the requested /103 denominator is shown separately as an unresolved
  traceability gap;
- the missing 3 points are not silently invented or awarded.

The official source hashes are:

- описание.docx: 8807A4DFB98FDCF7B25517E9443A8805A33542BA844D2285CECD3EE7B3FD6B2F;
- official NovaPay provider_api.yaml:
  415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551.

## Evidence classification

- PROVEN — directly observed in implementation plus reproducible test/run.
- PARTIALLY_PROVEN — demonstrated for a bounded fixture, but a material
  contract, environment or scope remains unverified.
- UNPROVEN — claimed or plausible, but no direct evidence in this checkout.
- CONTRADICTED — observed behavior conflicts with the criterion or a stated
  safety expectation.

Evidence is weighted in this order:

1. official DOCX/OpenAPI and direct runtime observation;
2. source and executable tests;
3. hand-authored ground truth and vectors;
4. README/research claims.

## A. Expert criteria — official maximum 100

### A1. Correctness of API specification parsing — 20

| Official subcriterion | Status | Strict points | Evidence | Lost points |
|---|---|---:|---|---|
| 8 — main API methods and request/response parameters are identified | PROVEN | 7/8 | Facts IR, OperationFact, OpenAPI validator, NovaPay/Aurora/Helios projections, benchmark semantic operation checks | 1: no proof across arbitrary OpenAPI constructs or production schema dialects |
| 7 — auth, operation statuses and errors are handled | PARTIALLY_PROVEN | 5/7 | AuthAnalyzer, StatusMapper, ErrorAnalyzer, committed Blueprint and spec-only runs | 2: business status meanings depend on case defaults; runtime error object/exception contract is open |
| 5 — webhook and other interaction conditions are handled | PARTIALLY_PROVEN | 4/5 | WebhookAnalyzer, ConditionalAnalyzer, idempotency, extra operations and vectors | 1: raw-body/hex facts partly come from preserved Q&A/defaults; event/status contradiction is not rejected |
| **Subtotal** |  | **16/20** |  |  |

### A2. Generation of integration service — 25

| Official subcriterion | Status | Strict points | Evidence | Lost points |
|---|---|---:|---|---|
| 10 — service forms and sends API requests | PARTIALLY_PROVEN | 6/10 | RubyProjection, generated fixtures, Aurora/Helios create vectors | 4: real client protocol absent; query fallback drops query; request transport is stub-only |
| 8 — responses, statuses and errors are processed | PARTIALLY_PROVEN | 4/8 | handle_response, error model, 202/204 tests, Retry-After fixture checks | 4: Hash-only response contract, no provider exception rescue, missing HTTP status is tolerated, unknown/error behavior not tested against host |
| 7 — incoming notifications and connection parameters are supported | PARTIALLY_PROVEN | 5/7 | HMAC runtime vectors, webhook config, BASE_URL/env and auth projection | 2: callback payload/host helper contract is stubbed; event/status contradiction can cause wrong action |
| **Subtotal** |  | **15/25** |  |  |

### A3. Correctness of data transformation — 15

| Official subcriterion | Status | Strict points | Evidence | Lost points |
|---|---|---:|---|---|
| 8 — request/response fields and statuses map correctly | PROVEN for bounded cases | 6/8 | independent semantic subsets, Aurora/Helios mappings, runtime status/webhook vectors | 2: no conflict vector for event/status and no real host result object |
| 7 — formats, required and optional fields are handled correctly | PARTIALLY_PROVEN | 5/7 | constraints, conditionals, money conversions, fixture generation and specs | 2: conditional prose parser is heuristic; generated runtime pattern/host types are not externally specified |
| **Subtotal** |  | **11/15** |  |  |

### A4. Universality — 15

| Official subcriterion | Status | Strict points | Evidence | Lost points |
|---|---|---:|---|---|
| 7 — works with APIs differing in methods, fields and parameters | PARTIALLY_PROVEN | 5/7 | Aurora and Helios have different paths, nested money, auth and statuses | 2: both are synthetic committed fixtures and use the same host stub |
| 5 — main logic is not tied to one provider | PARTIALLY_PROVEN | 4/5 | no NovaPay literals in generic generator; profiles/defaults boundary; production scan | 1: lexical operation heuristics and Space Payments profile remain domain-specific |
| 3 — new rules and unsupported elements are extensible/reported | PROVEN for current boundary | 2/3 | profiles, case defaults, REVIEW_REQUIRED/UNKNOWN, preserved extras | 1: remote refs unsupported by design; no plugin/schema extension contract |
| **Subtotal** |  | **11/15** |  |  |

### A5. Understandability of use and demonstration — 15

| Official subcriterion | Status | Strict points | Evidence | Lost points |
|---|---|---:|---|---|
| 6 — can be launched through a clear sequential process | PROVEN | 6/6 | README, bin/provider_compiler, Web Workbench, local RSpec/UI tests | 0 |
| 5 — setup, auth and use of generated integration are documented | PARTIALLY_PROVEN | 4/5 | README, generated INTEGRATION.md, fixtures, profiles | 1: production BaseService/client setup is explicitly not supplied |
| 4 — result and errors are presented clearly | PROVEN for local demo | 3/4 | Russian UI, evidence/review pages, fail-closed error pages | 1: no persistence/auth and no judge-access confirmation |
| **Subtotal** |  | **13/15** |  |  |

### A6. Technical implementation quality — 10

| Official subcriterion | Status | Strict points | Evidence | Lost points |
|---|---|---:|---|---|
| 6 — clear structure and separation of components | PROVEN | 6/6 | core/analysis/blueprint/generation/application/web separation | 0 |
| 4 — errors during parsing and generation are handled | PARTIALLY_PROVEN | 2/4 | typed compiler errors, UI error pages, CLI non-zero paths | 2: no resource budgets, runtime client exceptions are not normalized, symlink/regex risks remain |
| **Subtotal** |  | **8/10** |  |  |

### A strict total

**74/100**

This is intentionally lower than historical planning scorecards. The largest
deductions are for the missing real host contract and bounded runtime-only
verification, not for the high-level architecture.

## B. Technical jury — official maximum 100; requested denominator 103

The official DOCX lists these technical subcriteria. The task request's
additional /103 denominator has no source in the official document.

### B1. API specification parsing — 20

| Subcriterion | Status | Points | Evidence / loss |
|---|---|---:|---|
| 5 — available methods | PROVEN | 5/5 | Facts IR and operation mapping across committed fixtures |
| 5 — request/response parameters | PROVEN | 4/5 | schemas, constraints and field mappings; arbitrary schema composition not proven |
| 4 — auth requirements | PROVEN | 4/4 | AuthAnalyzer and runtime header/query projections on fixtures |
| 3 — statuses and errors | PARTIALLY_PROVEN | 2/3 | extracted and represented; business outcome and runtime exception semantics remain open |
| 3 — webhook and additional conditions | PARTIALLY_PROVEN | 2/3 | HMAC/conditionals/extras present; event/status conflict not fail-closed |
| **Subtotal** |  | **17/20** |  |

### B2. Integration service generation — 25

| Subcriterion | Status | Points | Evidence / loss |
|---|---|---:|---|
| 5 — generated service corresponds to Provider::BaseService | PARTIALLY_PROVEN | 1/5 | class inheritance/method names match; real BaseService absent and illustrative failure/client protocols differ |
| 5 — forms and sends requests | PARTIALLY_PROVEN | 3/5 | create vectors pass with stub; client signature and query fallback are not contract-safe |
| 4 — receives/processes operation status | PARTIALLY_PROVEN | 2/4 | mapping and 200/202 vectors pass; object response/missing status semantics unproven |
| 4 — responses and errors | PARTIALLY_PROVEN | 2/4 | Hash response and Retry-After paths pass; exceptions and real response class are not handled |
| 4 — incoming notifications | PARTIALLY_PROVEN | 2/4 | HMAC and callback vectors pass; contradictory event/status is unsafe |
| 3 — addresses and connection parameters | PROVEN for fixture model | 2/3 | sandbox URL/env/auth are projected; host gateway initialization remains undefined |
| **Subtotal** |  | **12/25** |  |

### B3. Data transformation correctness — 15

| Subcriterion | Status | Points | Evidence / loss |
|---|---|---:|---|
| 5 — statuses | PROVEN for ground-truth fixtures | 4/5 | independent mappings and vectors; conflict case absent |
| 4 — request/response fields | PROVEN for ground-truth fixtures | 3/4 | semantic comparator and Aurora/Helios vectors; real host result type absent |
| 3 — formats and units | PROVEN for bounded fixtures | 2/3 | major/minor x100 and major/major scale 1; arbitrary decimal/rounding policy not host-verified |
| 3 — required/optional fields | PARTIALLY_PROVEN | 2/3 | constraints/conditionals generated; prose heuristic and runtime client behavior remain open |
| **Subtotal** |  | **11/15** |  |

### B4. Universality and adaptability — 10

| Subcriterion | Status | Points | Evidence / loss |
|---|---|---:|---|
| 5 — differing methods and fields | PARTIALLY_PROVEN | 4/5 | Aurora/Helios structural differences, but synthetic and same host stub |
| 3 — logic separated from provider specifics | PARTIALLY_PROVEN | 2/3 | provider values live in fixtures/defaults/Blueprint; lexical/domain heuristics remain |
| 1 — extensible templates/rules | PROVEN | 1/1 | profiles, defaults and Blueprint projection boundaries |
| 1 — unsupported/ambiguous elements reported | PROVEN for tested cases | 1/1 | REVIEW_REQUIRED/UNKNOWN and safe generation gate |
| **Subtotal** |  | **8/10** |  |

### B5. Documentation and test materials — 13

| Subcriterion | Status | Points | Evidence / loss |
|---|---|---:|---|
| 5 — setup and auth description | PROVEN for prototype | 4/5 | README/generated integration guide; production host contract deliberately absent |
| 4 — methods, statuses and errors | PROVEN for bounded Blueprint | 3/4 | generated docs and error model; no live provider behavior |
| 4 — fixtures.json with requests/responses/notifications | PROVEN | 4/4 | generated artifacts and fixture tests |
| **Subtotal** |  | **11/13** |  |

### B6. Ease of use and demonstration — 10

| Subcriterion | Status | Points | Evidence / loss |
|---|---|---:|---|
| 4 — understandable launch | PROVEN | 4/4 | CLI, Web entrypoint, README commands |
| 3 — one sequential result-producing process | PROVEN for local demo | 3/3 | analyze/generate/verify and UI workflow |
| 3 — understandable messages/results | PROVEN for local demo | 3/3 | review evidence, blocked states, generated summary |
| **Subtotal** |  | **10/10** |  |

### B7. Implementation quality — 10

| Subcriterion | Status | Points | Evidence / loss |
|---|---|---:|---|
| 4 — readable architecture/code | PROVEN | 3/4 | clear layers; some runtime assumptions are implicit in generated template |
| 3 — parse/generation error handling | PARTIALLY_PROVEN | 2/3 | typed errors and gates; no resource budgets/runtime exception normalization |
| 3 — launch/configuration instruction | PROVEN for prototype | 2/3 | README and docs; real host integration remains unspecified |
| **Subtotal** |  | **7/10** |  |

### B strict total

**76/100 official technical denominator**

If a judge truly uses /103, the only defensible representation from current
evidence is:

**76/103 conservative lower bound, with 3 denominator points UNPROVEN**

This is not an official score conversion. The organizer must provide the
missing 3-point criteria before a legitimate /103 score can be calculated.

## C. Industry criteria — official maximum 20

| Criterion | Status | Strict points | Evidence / loss |
|---|---|---:|---|
| 6 — additional ideas | PARTIALLY_PROVEN | 4/6 | evidence ledger, Blueprint, explainability UI and semantic benchmark are meaningful additions; no external business validation |
| 6 — team presentation | UNPROVEN | 2/6 | repository contains demo script/UI, but no presentation or live judge delivery was audited |
| 8 — completeness of solution | PARTIALLY_PROVEN | 6/8 | complete hackathon prototype and artifacts; real BaseService, live provider and preproduction safety remain open |
| **Subtotal** |  | **12/20** |  |

## Score summary

| Section | Strict score | Published maximum | Requested maximum | Confidence |
|---|---:|---:|---:|---|
| A Experts | 74 | 100 | 100 | MEDIUM |
| B Technical jury | 76 | 100 | 103 | MEDIUM |
| C Industry | 12 | 20 | 20 | LOW/MEDIUM |
| **Official-denominator total** | **162** | **220** | — | MEDIUM |
| **Requested-denominator lower bound** | **162** | — | **243** | LOW until B addendum exists |

The numbers are audit estimates, not organizer marks. They intentionally do
not preserve previous 95/100, 18/20 or 100% readiness claims.

## Traceability map

| Claim area | Primary implementation evidence | Test/benchmark evidence | Limitation |
|---|---|---|---|
| OpenAPI facts and local refs | lib/provider_compiler/core.rb | pipeline/analyzer specs | no external parser corpus |
| Money host/provider units | profiles/space_payments_v1.yml, analysis.rb, Blueprint | semantic comparator, NovaPay/Aurora/Helios | host profile is project-supplied |
| Optional idempotency | analysis.rb, Blueprint, generated service | idempotency specs and vectors | retry policy is adapter policy |
| Operation IDs and extras | analysis.rb, blueprint.rb | mutation/Aurora/Helios semantic checks | no external provider |
| Webhook signature/status | analysis.rb, generation.rb | behavioral vectors | event/status contradiction uncovered by audit |
| BaseService compatibility | profiles/space_payments_v1.yml | test/support stubs | real production BaseService absent |
| Fail-closed generation | blueprint.rb, application.rb, web.rb | RSpec and mutation safety checks | unsafe runtime behavior can still exist after ACCEPT |
| Genericity | analyzer/profile boundaries | Aurora/Helios committed fixtures | synthetic, not held-out external |
| Ruby/no-neural restriction | Gemfile, lib/bin, CI, compliance audit | local CI-equivalent run | external judge environment not observed |
| GitHub submission availability | origin remote and repository metadata | GitHub API 404 unauthenticated | access state must be confirmed |

## Architectural impact

The audit does not justify a top-level architecture redesign. The evidence
supports retaining:

    Facts IR -> analyzers/evidence -> Review Manifest -> Blueprint
    -> projections -> verification

The required changes are boundary hardening:

- version and verify the real BaseService/client contract;
- add webhook contradiction checks;
- harden untrusted input and generated runtime behavior;
- separate external/held-out benchmark evidence from self-authored corpus;
- repair judge visibility.

These are correctness, evidence and operational controls, not a replacement
of the current architecture.
