# Spec-only success corpus v1

This is an independent, hand-authored validation lane for the generic
compiler. It is intentionally separate from `black_box_v1`, the mutation
benchmark and the provider-specific reference fixtures.

The corpus contains three synthetic but materially different OpenAPI
providers:

- LedgerOne: query API key, flat minor-unit amount with scale 100 and a
  signed callback;
- Orbit Remit: Bearer authentication, nested major-unit money and polling;
- Quanta Payout: header API key, minor-unit amount with scale 1000 and a
  signed callback.

The specifications contain explicit semantic evidence. There are no
CaseDefaults and no HUMAN_CONFIRMED overrides. `ground_truth.yml` and
`behavioral_vectors.yml` are written independently of the compiler output.

Run the lane from the repository root:

```text
ruby research/spec_only_success_v1/run.rb
```

The machine-readable result is written to `results.json`. Generated files
are placed below `tmp/spec_only_success_v1/` and are not part of the corpus.

This corpus is a validation fixture, not evidence that any named provider is
production-ready.
