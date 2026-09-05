# Compliance evidence

This document records a deterministic source-LOC audit for the Ruby majority
requirement. It counts participant-written source, not repository file counts.

The audit includes Ruby production source from `lib/**/*.rb` and `bin/*`, and
counts participant-written Web UI JavaScript/CSS in the denominator. It excludes
documentation, research prose, generated examples/artifacts, fixtures and data,
dependencies, `vendor/`, and `tmp/`. Blank lines and comment-only lines are not
counted. Tests are reported separately so the conservative production-only
result remains visible.

<!-- BEGIN GENERATED: RUBY_SHARE_AUDIT -->
**Methodology**

Participant-written source LOC only. Blank lines and comment-only lines are excluded. Generated examples, fixtures/data, documentation, dependencies, `vendor/`, and `tmp/` are excluded. Web UI JavaScript/CSS is participant-written source and remains in the denominator.

**Production source only**

- Ruby: 4110 LOC
- Other participant-written source: 321 LOC
- Total: 4431 LOC
- Ruby share: 92.8%

**Production + tests**

- Ruby: 5325 LOC
- Other participant-written source: 321 LOC
- Total: 5646 LOC
- Ruby share: 94.3%

Both measurements exceed the `>50%` requirement. The machine-readable file is [`research/ruby_share_audit.json`](../research/ruby_share_audit.json). Re-run `ruby bin/audit_ruby_share` after source changes.
<!-- END GENERATED: RUBY_SHARE_AUDIT -->

The machine-readable report is [`research/ruby_share_audit.json`](../research/ruby_share_audit.json).

Project license status: no repository `LICENSE` or `COPYING` file is currently
present. No license was added automatically; dependency licenses remain listed
in [`THIRD_PARTY.md`](../THIRD_PARTY.md).
