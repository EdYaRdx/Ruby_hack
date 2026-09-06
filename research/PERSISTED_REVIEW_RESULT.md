# GOAL 6.2 — Persisted Review Result

## Implemented contract

`provider_overrides.yml` is a versioned local artifact with schema version `1`.
Each entry must contain a decision id, a value and
`provenance: HUMAN_CONFIRMED`. The file also records:

- provider identity;
- spec fingerprint and root-document SHA-256;
- BaseService profile name/version;
- creation time;
- confirmed decisions only.

Credential-like keys are rejected recursively. API keys, webhook secrets and
runtime tokens are not persisted in an override.

## Safety behavior

- Changed OpenAPI/root or resolved local input -> `STALE_OVERRIDE` and no apply.
- Incompatible profile/version -> `PROFILE_MISMATCH` and no apply.
- Unknown decision id -> `UNKNOWN_DECISION_ID` and no apply.
- Malformed schema or credential-like data -> validation failure and no apply.
- Imported values are merged into defaults, re-analyzed, and exposed in the
  Review Manifest as `review_override: APPLIED`.

The fingerprint is validated against the loaded source document, whose
fingerprint includes resolved local input references rather than only the root
YAML path.

## Evidence

- `spec/persisted_review_spec.rb`: export/import, stale spec, profile mismatch,
  malformed schema, unknown decision and credential rejection — **3 examples,
  0 failures**.
- `spec/persisted_review_web_spec.rb`: Web export download and multipart import
  into a second workspace — **1 example, 0 failures**.
- CLI supports `export-review`, `--overrides`, and `--review-output`.
- Web Review exposes export/import actions without changing analyzer semantics.

## Limitation

Persistence is intentionally a local versioned file flow. There is no database,
multi-user locking or remote review service in scope. That is a deployment
concern, not hidden state in the compiler.
