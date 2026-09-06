# EXTERNAL AUDIT V2

Дата аудита: 2026-09-06  
Режим: независимый red-team / rubric audit, без доверия к historical
scorecards и README claims.

## Итог

Проект демонстрирует сильный исследовательский prototype: факты OpenAPI,
evidence, Review Manifest, Provider Blueprint, fail-closed decisions и
deterministic Ruby projection реально существуют в коде. Независимый
semantic comparator не сводится к сравнению одного decision field и
действительно обнаруживает неправильные operation и money mappings.

Но production-ready статус не доказан. В checkout нет реального
Provider::BaseService и нет внешнего runtime contract harness. Generated
adapter проверен против локального Hash-based stub, тогда как официальный
case description показывает другой набор response/client idioms. Поэтому
runtime compatibility с настоящим host остаётся открытым P0/P1 риском.

Дополнительно найдено:

1. Generated webhook handler выбирает canonical outcome по event и не
   проверяет конфликт event/status. Payload с event=payout.completed и
   status=failed может привести к approve_operation.
2. Runtime error handling рассчитан в основном на Hash response и не
   покрывает object response или exceptions от HTTP client так, как это
   предполагает illustrative BaseService example.
3. dispatch fallback не передаёт query в GET/POST client calls. Это
   ломает query API-key providers, если client не предоставляет общий
   request method.
4. Resolver проверяет lexical path containment, но не canonical realpath
   containment; symlink-based local $ref escape остаётся возможным. Нет
   depth/CPU/regex limits для untrusted specs.
5. Aurora generic_plus_safe_reusable_rules запускается с тем же
   empty-defaults input, что и pure_generic, поэтому это не отдельный
   experimental level.
6. 37 mutations — это 37 вариантов одного NovaPay-derived corpus, а не
   37 providers и не held-out external validation.
7. Remote GitHub visibility не подтверждена: unauthenticated GitHub API
   вернул HTTP 404 для origin repository. Для external judge это
   submission/visibility blocker, пока доступ не проверен из judge context.

Консервативный вывод:

- Hackathon prototype: YES.
- Semantic benchmark claims: valid only for the committed corpora and
  comparator assertions, not as general provider accuracy.
- Preproduction generated adapter: NO.
- Public/judge-facing repository availability: NOT PROVEN.
- Architecture redesign is not required by this audit. Требуются
  contract evidence, targeted runtime safety corrections и stronger
  validation boundary; top-level Facts IR -> Manifest -> Blueprint ->
  Generator architecture остаётся пригодной.

## 1. Источники и confidence

### Authoritative sources

| Source | Role | Integrity / confidence |
|---|---|---|
| C:\Users\Эдуард\Downloads\описание.docx | official case, illustrative BaseService contract and rubric | SHA-256 8807A4DFB98FDCF7B25517E9443A8805A33542BA844D2285CECD3EE7B3FD6B2F; direct source, HIGH |
| C:\Users\Эдуард\Downloads\provider_api.yaml | official NovaPay reference input | SHA-256 415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551; direct source, HIGH |
| fixtures/novapay_provider_api.yaml | committed copy of official input | byte-identical to Downloads copy, HIGH |
| research/REFERENCE_GROUND_TRUTH.md | preserved NovaPay fact/inference separation | project-authored, MEDIUM |
| research/GROUND_TRUTH_CORRECTIONS.md | preserved organizer Q&A interpretation | no standalone Q&A file was found; project-preserved record, MEDIUM |
| lib/, bin/, profiles/, fixtures/, spec/ | executable implementation and tests | directly inspected and locally executed, HIGH for observed behavior |
| README.md, docs/, prior research | claims and methodology | corroborating only, LOW/MEDIUM; never used as proof by itself |

The official DOCX was read from its OOXML document body. The packaged
render-to-PNG workflow could not run in this Windows environment because
Python/LibreOffice were unavailable; this is a review-tool limitation, not
an implementation result. Textual case and rubric sections were still
read directly from the official file.

No standalone organizer Q&A artifact was present in the checkout,
Downloads, or the available attachment inventory. Q&A-dependent facts are
therefore labelled as preserved project evidence, not independently
re-verified organizer files.

Historical files such as research/EXPECTED_SCORE.md and
research/SCORE_AUDIT.md are not used as current score evidence.

## 2. What was independently reproduced

Commands executed from the clean checkout:

    ruby research/benchmark/run.rb
    ruby research/benchmark/second_provider.rb
    ruby research/benchmark/third_provider.rb
    bundle exec rspec

Observed:

- reference mutation benchmark: 37/37 passed;
- decision accuracy: 100.0% on that corpus;
- safe decision coverage: 100.0% on that corpus;
- semantic ACCEPT accuracy: 100.0% on that corpus;
- critical false ACCEPTs: 0;
- generation attempts: 18/18 passed against the repository verification
  path;
- Aurora levels: 3/3 passed, semantic 100.0%, behavioral vectors 4/4;
- HeliosPay levels: 2/2 passed, critical false ACCEPTs 0;
- RSpec: 85 examples, 0 failures.

These are repeatable repository results. They are not proof of production
host compatibility, external provider coverage, or arbitrary OpenAPI
universality.

## 3. Architecture and claim boundary

The implemented flow is coherent:

    OpenAPI -> loader/ref resolver -> Facts IR -> analyzers/evidence
    -> Review Manifest -> Provider Blueprint -> Ruby projection
    -> generated docs/fixtures/smoke -> verification

The architecture is visible in:

- lib/provider_compiler/core.rb — loader, local refs, Facts IR, fingerprint;
- lib/provider_compiler/analysis.rb — operation/auth/money/status/webhook/
  idempotency/field/error analyzers;
- lib/provider_compiler/blueprint.rb — resolved Blueprint and validation;
- lib/provider_compiler/generation.rb — Ruby adapter and artifacts;
- lib/provider_compiler/application.rb — shared CLI pipeline;
- lib/provider_compiler/web.rb — local Demo Workbench over the same pipeline.

The following claims are supported:

- semantic decisions are outside the template;
- money.host and money.provider evidence are separated;
- Idempotency-Key spec requiredness and adapter policy are separate;
- local $ref closure participates in fingerprint inputs;
- /balance is preserved as non-blocking EXTRA_OPERATION by default;
- generation is blocked while critical decisions remain unresolved.

The following stronger claims are not supported:

- "verified against production BaseService";
- "runtime compatibility with Space Payments";
- "37-provider universality";
- "zero runtime correctness risk";
- "public GitHub availability" for an unauthenticated judge.

## 4. Runtime audit against the actual generated adapter

The generated template is in lib/provider_compiler/generation.rb. The
committed NovaPay projection is examples/novapay/service.rb.

| Surface | Observed implementation | Evidence status | Risk |
|---|---|---|---|
| Inheritance | generated class extends BaseService inside Provider | PROVEN | inheritance name is correct for the case wording |
| Required methods | check_conditions, create_request, process_callback, fetch_status exist | PROVEN | method presence only |
| Constructor | generated initialize accepts api_key/webhook_secret/client and does not call super | PARTIALLY_PROVEN | real BaseService initialization may be skipped; constructor signature is not defined by profile |
| Base pre-check | calls super(operation, request_method) when profile says so | PARTIALLY_PROVEN | only a Hash { "ok" => false } failure is propagated |
| Official failure idiom | case example uses base_result.failed?; generated checks Hash keys | PARTIALLY_PROVEN / CONTRADICTORY RUNTIME ASSUMPTION | a non-Hash failed result can be silently ignored |
| Request construction | creates method/path/url/headers/query/body and applies field mappings | PROVEN for generated fixture model | actual host client call remains unproven |
| POST client | fallback calls post(url, headers, body) positional | PARTIALLY_PROVEN | official illustration shows post(url, json: payload, headers: ...) |
| GET client | fallback calls get(url, headers) positional | PARTIALLY_PROVEN | official illustration shows get(url); signature not fixed by profile |
| Generic client | preferred request(method,url,headers,body,query) positional contract | UNPROVEN | no production client contract exists in repo |
| Query auth | request object contains query, but GET/POST fallback does not pass query | CONTRADICTED FOR THAT FALLBACK PATH | query API-key providers can lose credentials |
| Header auth | header strategy is emitted and vectors cover bearer/API key | PROVEN on stubs | real transport client not proven |
| Idempotency | optional spec fact stays false; if_available/always is ADAPTER_POLICY | PROVEN | in-memory generated key cache is not durable across restart |
| Money request | major-to-minor conversion uses Blueprint factor and exact integer check | PROVEN for tested vectors | host amount type contract is not externalized |
| Money response | inverse conversion is applied to mapped amount | PROVEN for tested vectors | response object shape remains a host risk |
| Documented success codes | only endpoint-declared statuses are accepted | PROVEN | correct fail-closed default for undocumented status |
| 204/no body | Hash response with status and no body returns ok with nil response | PROVEN by existing tests | external response object not covered |
| Empty body without status | failure provider response body is not an object | PROVEN from code | host-specific success semantics may differ |
| Missing HTTP status | body-only Hash can still be mapped by provider status | PARTIALLY_PROVEN | lack of transport status is not surfaced as a hard error |
| Unknown provider status | result is marked ok=false and preserves provider status | PROVEN | no hidden canonical mapping |
| HTTP errors | maps status/code, preserves error and Retry-After | PROVEN for Hash fixtures | raised client exceptions are not rescued |
| Retry-After | reads common case variants and returns metadata | PROVEN | no bounded retry executor is generated |
| Webhook HMAC | verifies raw body before parsing, constant-time compare | PROVEN for tested vectors | secret lifecycle/host callback contract not proven |
| Event/status consistency | canonical status comes from event only | CONTRADICTED SAFETY EXPECTATION | event/status contradiction can approve a failed payload |
| Unknown event | fails closed | PROVEN | good negative path |
| Callback action | maps approved/rejected to BaseService action if method exists | PARTIALLY_PROVEN | helper existence is checked only at runtime |
| Polling-only | callback path returns failure and generation can proceed | PROVEN in mutation tests | no broader polling lifecycle semantics |
| Extra operations | preserved in Blueprint/docs, not forced into four-method service | PROVEN | no generated callable for extras, by design |
| Path parameter | substitutes raw provider id into URL | PARTIALLY_PROVEN | no URL/path escaping |

Important source locations:

- generated constructor and condition handling:
  lib/provider_compiler/generation.rb:141-159;
- request/status/callback methods:
  lib/provider_compiler/generation.rb:161-215;
- transport dispatch:
  lib/provider_compiler/generation.rb:334-344;
- response handling:
  lib/provider_compiler/generation.rb:346-370;
- production projection has the same behavior:
  examples/novapay/service.rb:35-215.

### Concrete webhook contradiction

The handler reads provider_status from payload/body at
lib/provider_compiler/generation.rb:210, but selects canonical from
WEBHOOK events at line 212. It never checks that the terminal event and
status describe the same outcome. For example:

    event: payout.completed
    status: failed

is accepted after a valid signature and the event mapping can invoke
approve_operation. This is a real correctness/safety bug outside the
current semantic benchmark ground truth. It should be a P0 fix before any
live webhook processing.

### Concrete host-client mismatch

The official case description illustrates a response object accessed as
response.body['status'] and client calls using keyword arguments. The
generated adapter's response path only recognizes Hash-like transport
responses and its fallback calls are positional. The repository's
OrganizerContractHarness and benchmark stubs intentionally return Hashes,
so all current runtime passes are compatible with the harness but do not
close this gap.

## 5. Host contract audit

The official case description defines the four conceptual methods and shows
helpers such as success, failure, approve_operation and reject_operation.
It does not define a complete production class, constructor, client
protocol, response class, failure result class, or callback payload type.

The repository itself confirms this boundary:

- spec/support/organizer_contract_harness.rb says it is a
  "Test-only approximation";
- spec/support/base_service_stub.rb is test support;
- generated contract_smoke.rb embeds another local BaseService;
- lib/provider_compiler/web.rb:376-409 injects a local BaseService for the
  Demo Workbench;
- benchmark runners install their own BaseService classes.

Therefore:

- inheritance and conceptual method names are proven;
- concrete method/result/client compatibility is not proven;
- production readiness must remain NO until the real class or a
  contract-faithful external harness is supplied.

This is the single largest evidence gap in the project and the main reason
the technical score is reduced.

## 6. Genericity and NovaPay literal scan

The scan covered NovaPay, novapay, payout, RUB, kopecks, X-NovaPay,
payout.completed and numeric scale references across tracked production,
fixture, example, benchmark and documentation files.

| Occurrence class | Locations | Classification |
|---|---|---|
| Explicit reference/demo registry | lib/provider_compiler/web.rb:20-52, web_renderer.rb:111-112, application.rb:91-92 | ALLOWED REFERENCE SCOPE; UI demo and default CLI reference, not generic analyzer semantics |
| Host contract currency | profiles/space_payments_v1.yml:15-18 | HOST PROFILE FACT; not NovaPay provider knowledge |
| Generic lexical heuristics | lib/provider_compiler/analysis.rb:79, 122-127, 399-415 | GENERIC RULES; English/domain vocabulary bias remains |
| Provider projection | examples/novapay/* | GENERATED REFERENCE ARTIFACT; intentionally provider-specific |
| NovaPay fixture/defaults | fixtures/novapay_* | CASE INPUT / CASE DEFAULT; intentionally provider-specific |
| Mutation/semantic ground truth | research/benchmark/* | BENCHMARK DATA; intentionally NovaPay-derived |
| README/docs/research | README.md, docs/, research/ | CLAIMS/METHOD; not runtime literals |

No X-NovaPay, payout.completed or NovaPay webhook literal was found in the
generic generator template. The hardcoded NovaPay values are visible in the
demo registry, reference fixtures, generated example and benchmark data.
That separation is materially good.

Genericity is nevertheless limited:

- role discovery depends on lexical names such as payout/transfer/withdraw;
- the default host profile is Space Payments-specific;
- case defaults are required to resolve business semantics;
- remote refs are deliberately unsupported;
- there is no external held-out provider or live provider runtime.

Conclusion: GENERIC PIPELINE PROVEN for the three committed synthetic
profiles; UNIVERSAL PROVIDER COMPILER UNPROVEN.

## 7. Untrusted input and security review

### Positive controls

- YAML uses safe_load rather than arbitrary object deserialization;
- remote $ref is rejected;
- lexical $ref paths are restricted to the root directory;
- uploaded extensions are restricted to YAML/YML/JSON;
- web uploads are capped at 5 MiB and WEBrick has a body-size cap;
- upload filename is reduced to basename and sanitized;
- HTML output uses ERB::Util.html_escape in the renderer;
- workspace ids are random hex values;
- generated web preview does not call a provider network.

### Open risks

| Risk | Evidence | Severity |
|---|---|---|
| Symlink escape from lexical resolver root | lib/provider_compiler/core.rb:185-194 checks expand_path prefix but not File.realpath | P1 |
| Deep/recursive/alias-heavy YAML | core.rb:206-212 enables aliases and has no depth/node/CPU budget | P1 |
| Huge/complex CLI specs | web upload is capped, CLI loader has no equivalent size/depth limit | P1 |
| Regex DoS | provider pattern is compiled at runtime by Regexp.new in generated service | P1 |
| Generated Ruby class name from untrusted title | Util.camel is used for class name without constant-name validation | P1 |
| Untrusted server URL becomes generated default | RubyProjection uses Blueprint server URL as BASE_URL | P1 |
| Workspace exhaustion | in-memory store and temp dirs have no TTL, count limit or disk quota | P1 for exposed Web |
| No Web auth/CSRF/session isolation | local Demo Workbench is intentionally a single-user server | P1 if deployed |
| Example/fixture secret propagation | fixture synthesizer copies provider examples into generated artifacts | P1 until secret scan/redaction policy exists |
| Raw path parameter not escaped | generated status path inserts id.to_s directly | P2/P1 depending host input trust |
| No license file | repository has no LICENSE/COPYING | P2 compliance/reuse concern |

The local Web UI is acceptable as a localhost demo. It must not be treated
as a production multi-user review service without authentication,
authorization, persistence, CSRF protection, quotas and isolation.

## 8. Benchmark independence review

### What is genuinely independent

- research/benchmark/semantic_comparator.rb consumes expected semantic
  subsets and actual Blueprint; it does not call analyzers or derive
  expectations from Blueprint.
- spec/semantic_comparator_spec.rb proves that wrong operation, wrong
  factor, hidden resolved money, silently dropped UNKNOWN and correct
  semantics are distinguished.
- mutation cases execute the real loader/analyzers/Blueprint/generator
  path, not a policy-only table.
- Aurora and Helios use hand-authored semantic subsets and hand-authored
  runtime vectors.

### What is not external or independent in the strong sense

- all 37 mutation documents are derived from one NovaPay fixture;
- mutations, expected decisions, adjudications, semantic ground truth and
  vectors are maintained in the same repository by the project;
- three mutation labels are disputed/adjudicated (M12, M13, M32), so the
  final metric is conditional on those adjudications;
- no held-out provider, external reviewer label set, or live provider was
  used;
- Aurora and Helios are synthetic fixtures, not independently supplied
  provider packages;
- runtime vectors install a local BaseService stub;
- Aurora generic_plus_safe_reusable_rules calls the same empty-defaults
  pipeline as pure_generic and is not a distinct intervention.

### Metric interpretation

The observed 100.0% values mean:

    all committed hand-authored assertions passed

They do not mean:

    100.0% semantic accuracy over arbitrary providers

The honest claim is "independent comparator validation of a committed
reference corpus", not "external generalization proof".

## 9. Strengths

1. The design recognizes the semantic gap between OpenAPI shape and payment
   domain contract.
2. Money host/provider evidence is separated and directional conversion is
   explicit.
3. Optional idempotency is not mislabeled as a required spec fact.
4. Local $ref closure is included in source identity and preserved in
   Blueprint evidence.
5. Extra endpoints such as /balance are retained as non-blocking extras.
6. Review/UNKNOWN states are represented instead of silently dropped.
7. Generator, docs, fixtures and smoke are projections of one Blueprint.
8. The UI makes evidence and unresolved decisions visible.
9. The repository is Ruby-majority, offline-capable and free of neural
   runtime dependencies.

## 10. Priority findings

### P0

1. Webhook event/status contradiction can trigger the wrong terminal callback
   action. Add a negative runtime vector and fail closed on disagreement.
2. Do not claim production runtime readiness without the real BaseService or
   a contract-faithful external harness. The current verification is
   test-stub verification.
3. Confirm GitHub visibility from an unauthenticated judge account; current
   API request to origin returned 404.

### P1

1. Align client and response protocols with a versioned real host contract.
2. Pass query parameters through every supported client path.
3. Define exception-to-failure behavior for rate limits, unauthorized,
   timeouts and transport failures.
4. Harden resolver canonical paths, YAML budgets, regex limits and generated
   class names.
5. Add Web authentication/session isolation/persistence or explicitly keep
   the UI localhost-only.
6. Add secret redaction and trusted-server URL policy for generated artifacts.
7. Replace the duplicated Aurora level with a genuinely distinct experiment
   or relabel it as a repeated control.
8. Add an external/held-out provider and external ground-truth review before
   making universality claims.

### P2

1. URL-encode path identifiers.
2. Add an explicit LICENSE or document the intended distribution status.
3. Add observability for fingerprint, review resolution and generated
   artifact lineage.

## 11. Go/no-go

| Question | Result |
|---|---|
| Is the backend architecture coherent? | YES |
| Is the semantic comparator independently useful? | YES |
| Is the NovaPay semantic projection internally consistent? | YES, on committed evidence |
| Is generated runtime proven against real BaseService? | NO |
| Is webhook safety complete for contradictory payloads? | NO |
| Is benchmark external/held-out? | NO |
| Is public GitHub judge visibility proven? | NO |
| Is production deployment safe? | NO |

## Final verdict

EXTERNAL AUDIT V2

HACKATHON READY: NO (until repository visibility and official judge access are
confirmed; prototype evidence itself is substantial)

PREPRODUCTION READY: NO

SAFE TO START GOAL 6.1: NO

The next work should be a focused correctness/contract hardening pass, not
an architecture redesign.
