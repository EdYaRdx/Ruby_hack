# Post-checkpoint rubric audit: GOAL 6.5

Дата проверки: 2026-09-06
Исходное состояние: `6e0f534` (`docs: record final checkpoint UI acceptance`)
Официальный источник rubric: `описание.docx` (локальный attachment)
SHA-256 источника: `8807A4DFB98FDCF7B25517E9443A8805A33542BA844D2285CECD3EE7B3FD6B2F`
Официальная NovaPay OpenAPI: `provider_api.yaml` (локальный attachment)
SHA-256 OpenAPI: `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551`

## Назначение проверки

Это post-checkpoint audit, а не новая архитектурная концепция. Проверены только
два rubric gap: видимая multi-spec universality и доказательство outbound HTTP
границы generated adapter. Existing analyzer, Blueprint semantics и generator
остаются источником решений; новая проверка читает их результат и не добавляет
provider-specific ветвления.

## Official rubric mapping

| Область rubric | Evidence в репозитории | Статус после GOAL 6.5 |
|---|---|---|
| API parsing: methods, parameters, auth, statuses/errors, webhook/additional | `FactsBuilder`, analyzers, `provider_blueprint.json`, Analysis UI | PROVEN для зафиксированного scope |
| Integration service generation: BaseService, requests, responses, callbacks, config | `DeterministicGenerator`, generated `service.rb`, `INTEGRATION.md`, fixtures | PROVEN на generated artifacts и local runtime |
| Transformations: fields, statuses, formats, units | Blueprint field/status/money sections, independent semantic tests, previews | PROVEN для NovaPay/Aurora/Helios fixtures |
| Universality: different API shapes and no single-provider logic | landing comparison, generic pipeline, Aurora/Helios fixtures and specs | VISIBLE AND REGRESSION-COVERED для наблюдаемого корпуса |
| Use/demo: understandable flow and results | Web UI, `docs/DEMO.md`, actual Generate/Verification state | PROVEN |
| Technical quality and error handling | RSpec, syntax/smoke, fail-closed Review/Generate | PROVEN в CI scope |
| Outbound HTTP evidence | `TransportVerification`, localhost WEBrick + `Net::HTTP`, persisted readiness/UI state | PROVEN locally; no live provider claim |

Official technical-jury and expert totals are taken from the DOCX, not recomputed
from historical project scorecards. This audit does not convert local evidence
into a claim of production compatibility with an unknown Space Payments runtime.

## Multi-spec evidence

The landing page renders one evaluator-facing comparison built by running the
same `Pipeline` for three independent fixture/spec pairs:

| Case | Evidence visible in the comparison |
|---|---|
| NovaPay | API-key header auth, flat `amount`, `POST /payouts`, `GET /payouts/{payout_id}` |
| Aurora | Bearer header auth, nested `money.value`, `POST /transfers`, `POST /notifications` |
| HeliosPay | API-key query auth, nested `payment.amount`, `POST /funds`, HTTP `202`, `Retry-After` |
| Arbitrary upload | Same landing CTA enters the ordinary upload/analyze path with no case pack injection |

The comparison values are derived from current Blueprint output. The generic
analyzer has no NovaPay/Aurora/HeliosPay conditional branch; the provider names
occur only in fixtures/demo configuration and a non-executable explanatory
comment. `spec/web_spec.rb`, `spec/universality_spec.rb` and the provider
validation suites are the regression evidence.

## Outbound HTTP evidence

The evidence levels are deliberately separate:

| Level | Meaning | Result |
|---|---|---|
| Transport implemented | Generated service supports runtime-configured Base URL and client request dispatch | YES |
| Executable transport verified | Generated service sends real socket requests to an ephemeral localhost provider | YES |
| External provider sandbox executed | Real provider endpoint and credentials were used | NO — intentionally not executed |

`TransportVerification` starts a temporary local HTTP provider, sets the generated
provider Base URL through its runtime environment contract, loads the generated
service and uses `Net::HTTP`. It records and checks, independently of decision
equality:

- create method and path;
- query keys and authentication location;
- JSON body and `Content-Type`;
- status method, substituted path parameter and authentication;
- response parsing and canonical status mapping.

The machine-readable result is persisted under `runtime_transport` in
`integration_readiness.json`; `INTEGRATION_READINESS.md` and the Generate page
expose the same actual state. Secrets and the ephemeral `Host` port are redacted.
The external result is explicitly `executed: false` with reason
`No real sandbox endpoint/credentials supplied`.

## Architecture impact

**No architecture redesign.** The correction is limited to:

1. an evidence verifier at the verification boundary;
2. persisted readiness projection of that verifier result;
3. a UI projection of existing demo pipelines and verification state;
4. focused regression tests and documentation.

Facts, analysis, Blueprint, generation semantics, review safety and the existing
BaseService boundary are unchanged. The new verifier consumes generated artifacts
and does not infer or repair semantic mappings.

## Remaining honest limitation

The project proves deterministic parsing, semantic mapping and generated-adapter
transport against local fixture-backed providers. It does not prove a live call to
a real payment provider sandbox, production credentials, or compatibility with an
undocumented external `BaseService` implementation. Those require an explicitly
configured endpoint, credentials and an authorized environment outside CI.
