# NovaPay spec-only baseline

This report measures the official NovaPay OpenAPI input with no provider-specific
defaults. It is separate from the seven-case mutation lane.

<!-- BEGIN GENERATED: NOVAPAY_SPEC_ONLY_BASELINE -->
**Official input**: `fixtures/novapay_provider_api.yaml`
**Host profile**: `profiles/space_payments_v1.yml`
**Provider defaults**: none (spec-only)

| Metric | Result |
|---|---:|
| Total decisions | 14 |
| Accepted decisions | 10 |
| Review-required decisions | 4 (28.6%) |
| Blocking entries | 3 |
| Decision automation | 10/14 (71.4%) |
| Fully auto-ready | 0/1 (0.0%) |
| Critical false ACCEPTs | 0 |
| Unsafe generation attempts | 0 |

Automatic facts are accepted only where the official specification provides sufficient evidence. Remaining review concerns are preserved in the Review Manifest; the spec-only run does not generate an adapter.
<!-- END GENERATED: NOVAPAY_SPEC_ONLY_BASELINE -->
