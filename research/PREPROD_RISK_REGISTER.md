# PREPROD RISK REGISTER

Дата: 2026-09-06  
Scope: generated Ruby adapter, compiler input boundary, local Web UI,
benchmark evidence and judge-facing delivery.

## Risk rating

- P0 — unsafe financial/callback behavior or release blocker; must close
  before any live integration.
- P1 — material correctness/security/evidence risk; must have a mitigation and
  explicit owner before preproduction.
- P2 — important hardening or operational debt; can follow a controlled pilot.

## Register

| ID | Priority | Area | Finding | Evidence | Impact | Gate | Status |
|---|---|---|---|---|---|---|---|
| R-001 | P0 | Webhook correctness | event is mapped to canonical status without checking payload status; signed payout.completed + status: failed can invoke approve_operation | lib/provider_compiler/generation.rb:201-215; no contradictory vector in current benchmark | wrong terminal financial state | hard block live webhook processing | OPEN |
| R-002 | P0 | Host contract | real Provider::BaseService, client protocol and result classes are absent; all runtime verification uses stubs/harnesses | spec/support/organizer_contract_harness.rb; generation.rb:825-833; web.rb:376-409 | generated adapter may fail or bypass host checks in production | obtain real class or contract-faithful external harness | OPEN |
| R-003 | P0 | Delivery | unauthenticated GitHub API returned 404 for origin repository | origin is https://github.com/EdYaRdx/Ruby_hack.git; read-only API check | judge cannot inspect submission | verify public visibility or judge access | OPEN |
| R-004 | P1 | Base check safety | generated code propagates only Hash {"ok": false}; official case example uses base_result.failed? | generation.rb:148-158; official description.docx example | host rejection can be ignored if result is an object | define result protocol and add negative runtime test | OPEN |
| R-005 | P1 | HTTP client | fallback POST/GET signatures differ from official illustration; query is omitted in fallback dispatch | generation.rb:334-343; official case example | auth/request failure for query-key or keyword-only clients | version client interface in profile and test both adapters | OPEN |
| R-006 | P1 | Transport errors | generated code maps response errors but does not rescue provider client exceptions | generation.rb:180-195, 346-370 | timeout/rate-limit/unauthorized exceptions escape host service | define exception mapping and test it | OPEN |
| R-007 | P1 | Webhook payload | process_callback requires raw_body/signature-shaped payload, while host callback payload contract is not defined | generation.rb:198-215; official example is illustrative only | integration adapter may not receive verifiable raw bytes | publish callback ingress contract and test raw bytes | OPEN |
| R-008 | P1 | Idempotency durability | generated always/if_available policy caches generated UUIDs in process memory | generation.rb:168-174 | restart/retry can use a new key and duplicate a payout | require host-provided stable key or durable key store | OPEN |
| R-009 | P1 | Resolver security | root containment uses expand_path prefix but does not resolve symlinks | core.rb:185-194 | local $ref can read outside intended tree through symlink | canonicalize realpath and reject links outside root | OPEN |
| R-010 | P1 | Resource exhaustion | no CLI size/depth/node/time budgets; aliases and recursive structures are enabled | core.rb:206-212 and recursive resolver | malicious spec can exhaust CPU/stack/memory | enforce bounded parser/resolver budgets | OPEN |
| R-011 | P1 | Regex safety | provider patterns are compiled with Regexp.new at generated runtime | generation.rb:273-305 | catastrophic backtracking or invalid regex can block service | validate/limit regex complexity or use safe subset | OPEN |
| R-012 | P1 | Generated code safety | provider title is converted to Ruby class name without validating constant syntax | generation.rb:12 and core.rb Util.camel | malformed title can produce invalid code or denial of generation | validate class name and fail before artifact creation | OPEN |
| R-013 | P1 | Outbound target trust | server URL from untrusted spec becomes generated BASE_URL default | generation.rb:26-37 and template | running generated output from hostile spec can exfiltrate credentials | require explicit trusted base URL or allowlist | OPEN |
| R-014 | P1 | Web isolation | Web Workbench has no auth, CSRF, session isolation or persistent review store | web.rb:411-460 and Application routes | public deployment permits workspace abuse/data exposure | keep localhost-only or add security boundary | OPEN |
| R-015 | P1 | Workspace quota | workspaces/temp files are retained in memory until process cleanup; no TTL/count/disk quota | web.rb:411-460 | repeated uploads can exhaust memory/disk | add quotas/TTL and bounded cleanup | OPEN |
| R-016 | P1 | Fixture leakage | generated fixtures/docs can inherit provider examples verbatim | generation.rb FixtureSynthesizer and generated artifacts | credentials or sensitive sample data can enter artifacts | redact secrets and scan generated output | OPEN |
| R-017 | P1 | Benchmark independence | all 37 mutations derive from NovaPay and ground truth lives in same repository | research/benchmark/mutations.json; semantic_ground_truth.yml | 100% can overstate generalization | add held-out/external corpus and independent adjudication | OPEN |
| R-018 | P1 | Benchmark level duplication | Aurora pure_generic and generic_plus_safe_reusable_rules use same empty defaults path | research/benchmark/second_provider.rb:33-38 | reported level comparison has no experimental contrast | relabel repeated control or implement distinct input | OPEN |
| R-019 | P1 | Runtime coverage | current vectors omit event/status contradiction, client exceptions, query fallback, response objects and restart retry | fixtures/*behavioral_vectors.yml; runner stubs | safety gaps remain invisible | add negative and host-contract vectors | OPEN |
| R-020 | P2 | URL handling | provider operation id is inserted into path without URL encoding | generation.rb:187-192 | malformed identifiers can alter request target | encode path segment with host-approved utility | OPEN |
| R-021 | P2 | HTTP semantics | a body-only response with a recognized provider status can be accepted without transport status | generation.rb:346-365 | transport failures may be misclassified as business success | require explicit response protocol | OPEN |
| R-022 | P2 | Review durability | review resolutions live in Workspace object and disappear on process restart | web.rb:65-83, 411-460 | human decision audit trail is lost | persist manifest/resolution records | OPEN |
| R-023 | P2 | License | no LICENSE or COPYING file is present | repository root and docs/COMPLIANCE.md | distribution/reuse ambiguity | choose and publish license or explicit policy | OPEN |
| R-024 | P2 | Documentation consistency | official rubric in DOCX totals technical jury at 100, while audit request says 103 | official DOCX section Технические жюри | score comparison may be misreported | obtain organizer addendum | OPEN |

## P0 release gates

Preproduction cannot start until all are true:

1. R-001 has a fail-closed event/status consistency rule and negative test.
2. R-002 has a real BaseService/client/result contract or an external
   contract-faithful harness.
3. R-003 is resolved from the judge's actual unauthenticated access context.

## P1 exit experiments

The following experiments are sufficient to turn the biggest unknowns into
evidence without redesigning the pipeline:

### E1 — Real host contract

Load a generated NovaPay and Aurora service against the actual
Provider::BaseService and client. Exercise:

- constructor and required super initialization;
- check_conditions parent success and parent failure;
- host result failed? semantics;
- failure(status, code, message) argument types;
- create request with keyword and positional client forms;
- status response object with body and HTTP status;
- 201, 200, 202, 204, empty body, missing HTTP status;
- rate-limit/unauthorized/timeout exceptions;
- callback raw bytes and helper actions.

Pass condition: no stub-specific branches are required and every result
matches the host contract.

### E2 — Webhook contradiction

Add runtime expectations for:

    signed event=payout.completed, status=failed -> failure/review, no approve
    signed event=payout.failed, status=completed -> failure/review, no reject
    unknown event with known status -> fail closed
    valid event/status pair -> expected callback action

Pass condition: contradictory terminal payloads never invoke a terminal
approve/reject action.

### E3 — Input boundary fuzzing

Run bounded tests for:

- symlinked local $ref outside root;
- ../ and mixed-separator refs;
- recursive refs and cyclic YAML aliases;
- deeply nested documents;
- 5 MiB boundary and CLI oversized input;
- invalid and pathological regex;
- title beginning with a digit or containing unusual Unicode;
- server URL containing credentials or non-HTTPS schemes.

Pass condition: deterministic rejection with bounded resource usage and no
outside-file read.

### E4 — Query/header client matrix

Use a contract-faithful fake client with:

- request(method, url, headers, body, query);
- get(url);
- get(url, headers, query);
- post(url, json:, headers:);
- explicit query API-key auth;
- bearer/header auth;
- idempotency present, absent and always policy.

Pass condition: URL, headers, query and body are identical to independent
expectations on every supported client contract.

### E5 — Benchmark holdout

Add at least one provider fixture not derived from NovaPay, with ground truth
created before running the compiler and reviewed by a person who did not
write the analyzer. Keep mutation corpus results separately labelled.

Pass condition: reports distinguish:

- committed reference corpus pass rate;
- held-out provider semantic accuracy;
- runtime contract pass rate;
- false ACCEPT safety rate.

## Threat-model checklist

| Boundary | Current behavior | Preprod decision |
|---|---|---|
| OpenAPI upload | local parse, 5 MiB Web cap | safe for localhost demo; not public production |
| CLI spec path | arbitrary local file path | trusted operator only until budgets/sandboxing exist |
| Local refs | remote blocked, lexical root check | not safe for hostile directory trees with symlinks |
| Case defaults | explicit project input | must be scoped/fingerprinted and reviewed |
| Generated BASE_URL | taken from Blueprint server | trust input or require explicit override |
| Credentials | passed at runtime, no live calls by compiler | generated artifact handling still needs secret scan |
| Review state | in-memory | not durable/auditable across restart |
| Web routes | random workspace ids, no auth | localhost-only |
| Generated Ruby | deterministic projection | requires host contract and runtime security tests |
| Benchmark | independent comparator, same-repo ground truth | evidence, not external assurance |

## Owner-oriented action order

1. Host contract owner: close R-002/R-004/R-005/R-006/R-007.
2. Payment safety owner: close R-001/R-008/R-019.
3. Input security owner: close R-009/R-010/R-011/R-012/R-013.
4. Web/demo owner: close R-003/R-014/R-015/R-022.
5. Evaluation owner: close R-017/R-018/R-024.
6. Release owner: close R-016/R-020/R-021/R-023.

## Final status

PREPRODUCTION READY: NO

SAFE TO START GOAL 6.1: NO

The register does not require a new top-level architecture. It requires
evidence and hardening at the existing runtime, input and verification
boundaries.
