# GOAL 6.3 — Cross-Platform Green Matrix Result

## Original failure

The original run was [34022813293](https://github.com/EdYaRdx/Ruby_hack/actions/runs/34022813293)
for commit `2dd7a23`. All four matrix jobs passed checkout, setup, bundle,
RSpec, syntax, Ruby-share, benchmarks, gem build and both updater commands. All
four failed only at `Verify reproducibility and repository hygiene`.

The updater changed only the tracked artifact
`research/black_box_v1/failures.json`.

Ubuntu Ruby 4.0 produced this path-only difference:

```diff
- "source": "C:/Projects/Ruby_hack/research/black_box_v1/baseline_results.json",
+ "source": "/home/runner/work/Ruby_hack/Ruby_hack/research/black_box_v1/baseline_results.json",
```

Windows Ruby 3.3 produced the same absolute-path difference, with the runner
path `D:/a/Ruby_hack/Ruby_hack/...`, and also rendered an empty `failures`
array as a multiline array instead of `[]`. Ruby 4.0 used the one-line empty
array representation. The failure classes were platform-specific absolute
paths and Ruby-version JSON pretty-printer formatting; there was no semantic,
runtime or black-box decision failure.

## Fix

The deterministic fix:

- writes repository-facing text as UTF-8 with LF line endings and a final
  newline through `ProviderCompiler::Util.write_text` and equivalent script
  helpers;
- stores the black-box failure report source as a repository-relative path with
  `/` separators;
- canonicalizes empty JSON arrays in the black-box report independently of the
  Ruby pretty-printer layout;
- keeps the CI hygiene check strict and adds `git status --short` diagnostics
  before the failing diff is printed;
- writes the copied example OpenAPI file through the same LF-only policy.

Semantic compiler changes: **NONE**.

Frozen black-box corpus inputs changed: **NO**.

Benchmark ground truth changed: **NO**.

## Local verification

| Check | Result |
| --- | --- |
| Full RSpec | PASS — 106 examples, 0 failures, 1 expected Windows symlink pending |
| Ruby syntax | PASS — 33 checked files, 0 failures |
| Reference mutation benchmark | PASS — 37/37; semantic areas 100% |
| NovaPay spec-only benchmark | PASS — 7/7; critical false ACCEPTs 0; unsafe generation 0 |
| Aurora validation | PASS — 3/3 |
| HeliosPay validation | PASS — 2/2 |
| Frozen black-box benchmark | PASS — 12/12; critical false ACCEPTs 0; unsafe generation 0; crashes 0 |
| Generated adapter localhost HTTP E2E | PASS — release vectors cover auth, money, errors, webhook and idempotency |
| Gem build | PASS — `provider_compiler-0.1.0.gem`; metadata warnings only |
| `update_docs` first and second runs | PASS — idempotent |
| `update_examples` first and second runs | PASS — idempotent across 9 files |
| Generated text line-ending audit | PASS — 16 generated files are LF-only, UTF-8 and final-newline terminated |
| `git diff --check` | PASS |
| Production Ruby share | PASS — 90.1% |

The frozen corpus paths introduced at `7257a89` —
`research/black_box_v1/specs`, `ground_truth.yml` and `MANIFEST.json` — have no
diff from that freeze point. The later runtime-hardening fixture
`runtime_vectors.yml` was introduced by `64f9988` and is unchanged since that
commit.

## Remote matrix

The first fixed commit `aef1f98` was validated by
[GitHub Actions run 34023508224](https://github.com/EdYaRdx/Ruby_hack/actions/runs/34023508224).
The workflow concluded `success`, and every required job passed:

| Job | Result |
| --- | --- |
| Windows / Ruby 3.3 | PASS |
| Windows / Ruby 4.0 | PASS |
| Ubuntu / Ruby 3.3 | PASS |
| Ubuntu / Ruby 4.0 | PASS |

Each job passed the reproducibility/hygiene step as well as the semantic,
runtime, packaging and benchmark checks. The documentation and LF-only writer
hardening in this result are subsequently validated by the CI run triggered by
the commit containing this report.

## Documentation and acceptance boundary

- `research/PREPROD_ACCEPTANCE.md`: updated with observed Linux, Windows,
  Ruby 3.3, Ruby 4.0 and cross-platform PASS evidence; real Space
  `Provider::BaseService` remains PENDING.
- `research/FINAL_EXTERNAL_AUDIT.md`: stale local-only Linux/Ruby 3.3 claim
  removed; remote matrix evidence recorded without calling it production sign-off.
- `research/RELEASE_ENGINEERING_RESULT.md` and `INTEGRATION_READINESS.md`:
  current platform evidence synchronized.
- README generated runtime wording now states that live provider calls are not
  performed, while generated transport is verified through local HTTP E2E
  without external network. The CI badge points to the green workflow.

The compiler core is safe to freeze and ready for checkpoint/demo use. Real
Space production integration remains unproven because the actual
`Provider::BaseService`, client/result classes and staging contract were not
supplied. An independent human reviewer also remains an external pending item.
No architecture redesign is required by the reproducibility finding.

## Final acceptance

| Gate | Result |
| --- | --- |
| Cross-platform runtime observed | YES |
| Cross-version Ruby observed | YES |
| Cross-platform reproducibility | PASS |
| Real generated localhost HTTP | PASS |
| Real Space `Provider::BaseService` available | NO |
| P0 remaining | NONE |
| HACKATHON READY | YES |
| CHECKPOINT READY | YES |
| PREPRODUCTION CORE READY | YES |
| REAL SPACE PRODUCTION INTEGRATION PROVEN | NO |
| CI READY | YES |
| SAFE TO FREEZE | YES |
| READY TO PUSH | YES |
