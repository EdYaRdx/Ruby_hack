# Frozen black-box provider corpus v1

This corpus is an independent, synthetic validation set for Provider Compiler.
It was designed before running the current implementation and is not derived
from analyzer aliases or existing benchmark mutations.

All cases use `profiles/space_payments_v1.yml` and are intentionally varied in
authentication, operation naming, money representation, webhook shape,
parameters, OpenAPI composition, and unsupported input. The expected answers
in `ground_truth.yml` are hand-authored from each provider specification and
the host profile.

The corpus is synthetic. It is evidence about reproducible compiler behavior,
not evidence that these providers exist or that arbitrary production OpenAPI is
supported.

## Freeze rules

- `specs/**` and `ground_truth.yml` are frozen after the corpus commit.
- An objective mistake is recorded in `ERRATA.md`; expected answers are not
  silently rewritten to improve implementation results.
- `MANIFEST.json` records SHA-256 values for every input.
- Baseline and final results are written outside the frozen input files.

## Case index

| Case | Focus |
|---|---|
| `01_header_create` | header API key, 201 create, provider status |
| `02_query_202` | query API key, 202 create without create status |
| `03_bearer_polling` | bearer, polling-only, extra operation |
| `04_unsupported_auth` | unsupported OAuth2 scheme |
| `05_missing_operation_id` | structurally named operations without operationId |
| `06_nested_major` | nested major-unit money |
| `07_scale_1000` | minor-unit money with scale 1000 |
| `08_ambiguous_money` | unresolved money semantics |
| `09_required_parameters` | required custom query and header parameters |
| `10_webhook_contradiction` | explicit HMAC webhook and contradictory event/status |
| `11_openapi_shapes` | XML-only media, allOf/oneOf/anyOf, callbacks |
| `12_local_refs` | multi-file local `$ref`, server variables, extra endpoint |

