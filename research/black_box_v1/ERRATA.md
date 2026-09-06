# Corpus errata

## 2026-09-06 — `05_missing_operation_id`

The hand-authored case records the absence of `operationId` as a review-worthy
provider fact. The existing compiler contract intentionally permits a
structural `method + path + schema` fallback when the operation identity is
otherwise deterministic; this behavior is covered by the pre-existing
`M05` regression and is not an unsafe semantic guess by itself.

Therefore the independent comparator treats `missing_operation_id` as an
advisory corpus observation, not as a mandatory `unsupported_features`
diagnostic. The frozen OpenAPI and ground truth files are unchanged.

