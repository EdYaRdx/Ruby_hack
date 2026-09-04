# Scorecard GOAL 2

Этот исторический scorecard фиксирует реализованный на этапе GOAL 2 vertical
slice и его границы. Он не утверждает production readiness или универсальное
покрытие provider-ов; последующие результаты зафиксированы в документах GOAL
3 и GOAL 3.5.

| # | Gate | Result | Evidence |
|---:|---|---|---|
| 1 | OpenAPI load/validation | PASS | `lib/provider_compiler/core.rb`; `spec/pipeline_spec.rb` |
| 2 | Local `$ref` resolution | PASS | immutable resolved Facts IR and closure tests |
| 3 | Fingerprint includes resolved local inputs | PASS | root hash, ref closure, loaded-file hashes, resolver policy |
| 4 | Provider-independent Blueprint validation | PASS | conversion is checked from units/direction/provenance; no NovaPay-specific validator rule |
| 5 | Generic money model | PASS | major/major identity, configurable scale 100/1000, exact decimal factor metadata and unknown-scale blocking tests |
| 6 | Generic auth strategies | PASS | header API key, query API key, Bearer tests |
| 7 | Field mappings | PASS | request/response mappings with direct and transformed provenance |
| 8 | Request constraints | PASS | required, enum, pattern, length and minimum preservation |
| 9 | Status mapping | PASS | explicit provider-to-host mappings; unknown values fail closed |
| 10 | Error model | PASS | HTTP status, provider code, category, retryability, action and `Retry-After` |
| 11 | Request construction | PASS | `build_create_request` returns a deterministic request descriptor and enforces exact host-to-provider integer conversion |
| 12 | Request execution | PASS | `create_request` dispatches through a configured client |
| 13 | Status execution | PASS | `fetch_status` uses GET, maps status and converts provider amount as exact decimal without an integer-target check |
| 14 | Extra operations | PASS | cancel and `/balance` are preserved as non-blocking `EXTRA_OPERATION` values |
| 15 | Webhook safety | PASS | raw-body HMAC verification, constant-time comparison, event mapping, fail-closed input |
| 16 | Callback action binding | PASS | terminal actions come from `BaseServiceProfile`; in-progress has no terminal action; missing binding fails safely |
| 17 | Idempotency safety | PASS | OpenAPI `required: false` is separate from adapter policy; retry key is preserved |
| 18 | Generated artifacts | PASS | Blueprint, manifest, Ruby, fixtures, contract smoke harness and integration documentation |
| 19 | CLI | PASS | `analyze`, `inspect`, `generate`, `verify`; `--out` and `--output` |
| 20 | Golden verification | PASS | official YAML SHA-256 `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551`; 21 RSpec examples green |
| 21 | Mutation benchmark and second provider | NOT RUN at GOAL 2 snapshot | явно исключены этой hardening goal; позднее проверены в GOAL 3/3.5 |

## Аудит ground truth

Официальный `provider_api.yaml` повторно проверен напрямую. Organizer Q&A
использован для raw-body/hex webhook semantics и host callback context.
Generated Blueprint содержит официальный sandbox URL, `getPayoutStatus`,
optional `Idempotency-Key`, major-RUB host amount, minor/kopeck provider amount
и directional `×100`/`÷100` conversions с явным scale `100`. Host evidence —
`BASE_SERVICE_PROFILE`; provider evidence хранится отдельно как
`SPEC_DESCRIPTION` плюс `CASE_DEFAULT`. `/balance` остаётся сохранённой
non-blocking extra operation.

## Влияние на архитектуру

Hardening corrections не требуют новой архитектуры. Они представлены внутри
существующего pipeline Facts IR → analyzers/evidence → Blueprint → deterministic
projection → verification. Реализация добавляет только локальные проверки
direction/scale и profile capability checks в существующих границах модулей;
новая high-level feature или pipeline не появляется.

Запрошенного файла `ARCHITECTURE_FREEZE_V1` не было в worktree; доступными
constraints послужили существующие `FINAL_VERDICT.md`,
`PROVIDER_BLUEPRINT_V1.md` и `ARCHITECTURE_INVARIANTS.md`.
