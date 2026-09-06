# Трассировка official rubric

Документ связывает критерии из официального `описание.docx` с текущей
реализацией, UI evidence, тестами и честными ограничениями. Это traceability
matrix, а не self-awarded score. Официальный DOCX содержит экспертный и
technical-jury rubric с опубликованными максимумами; отдельная историческая
просьба считать technical section как `/103` не подтверждена источником и здесь
не используется как основание для баллов.

Источники:

- official rubric: `описание.docx` (локальный attachment), SHA-256
  `8807A4DFB98FDCF7B25517E9443A8805A33542BA844D2285CECD3EE7B3FD6B2F`;
- reference OpenAPI: `provider_api.yaml` (локальный attachment), SHA-256
  `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551`;
- текущие generated metrics: [`docs/BENCHMARK.md`](../docs/BENCHMARK.md) и
  generated blocks в [`README.md`](../README.md).

## Классификация evidence

- **PROVEN** — непосредственно наблюдается в implementation и воспроизводимом
  тесте или runner-е;
- **BOUNDED** — доказано для зафиксированного fixture/corpus scope;
- **PARTIAL** — часть поведения доказана, но существенная граница остаётся;
- **NOT CLAIMED** — для этого checkout нет достаточного evidence.

## Expert rubric

| Официальный критерий | Implementation | UI evidence | Test / run evidence | Честное ограничение |
|---|---|---|---|---|
| API parsing: methods, request/response parameters | `OpenAPILoader`, `OpenAPIValidator`, `FactsBuilder`, `OperationMapper` | Analysis показывает operations, paths, parameters и schemas | `spec/*`, NovaPay/Aurora/Helios fixtures, black-box | не заявляется поддержка всех dialects и schema compositions |
| Auth, statuses и errors | `AuthAnalyzer`, `StatusMapper`, `ErrorAnalyzer` | Analysis/Review показывает evidence и decisions | semantic comparator, provider benchmarks, runtime vectors | business status meanings могут требовать explicit defaults; production response class не задан |
| Webhook и дополнительные условия | `WebhookAnalyzer`, `ConditionalAnalyzer`, extra-operation preservation | Analysis/Preview показывает signature, event и conditional facts | webhook vectors, semantic comparator, RSpec safety | live webhook provider не вызывается |
| Generation service: requests и responses | `RubyProjection`, `DeterministicGenerator` | Generate показывает artifacts и readiness | syntax, contract smoke, release E2E, localhost transport | production `Provider::BaseService` отсутствует в checkout |
| Notifications и connection parameters | generated webhook/config sections, runtime Base URL | Generate и `INTEGRATION_READINESS.md` | runtime vectors и transport verifier | production host initialization contract не предоставлен |
| Data transformations: fields, statuses, units | Blueprint field/money/status mappings | Analysis, Review и Preview | independent semantic checks, NovaPay/Aurora/Helios vectors | coverage ограничена committed ground truth |
| Understandable use and demo | Web Workbench, CLI, generated docs | `docs/DEMO.md`, Russian UI, CLI fallback | `spec/web_spec.rb`, full RSpec | local prototype, без hosted deployment |
| Technical quality и error handling | layered Ruby implementation, typed errors, safety gates | controlled Review/Generate error states | RSpec, Ruby syntax, CI matrix | runtime compatibility с неизвестным host protocol не доказывается |

## Technical-jury rubric

| Официальный критерий | Implementation | UI / artifact evidence | Test / run evidence | Ограничение |
|---|---|---|---|---|
| Available methods | Facts IR и generic operation mapping | Analysis operation cards | reference, provider и black-box suites | lexical/domain heuristics имеют ограниченный scope |
| Request/response parameters | schema extraction, constraints, field mappings | Analysis и generated `INTEGRATION.md` | semantic comparator и fixtures | произвольные compositions не обещаются |
| Auth requirements | header/query API key и Bearer strategies | Auth section и generated request docs | runtime localhost HTTP checks | OAuth2/cookie/unknown schemes не поддерживаются автоматически |
| Statuses и errors | status map, HTTP success categories, error model | Review evidence и readiness | provider vectors, benchmark | live failure objects/exceptions не проверены |
| BaseService integration | profile-driven class/method projection | generated `service.rb` | contract smoke и local harness | реальный Space Payments BaseService отсутствует |
| Forms and sends requests | generated client dispatch и runtime-configurable URL | Generate `HTTP transport` block | captured localhost create/status requests | external sandbox не вызывался |
| Notifications | HMAC verification и callback action binding | Preview webhook result | behavioral vectors | external webhook delivery не проверена |
| Formats, units, required/optional | constraints, conversions, conditionals | Review/Preview | NovaPay major→minor ×100, Aurora major→major, Helios minor→major | не заявляется полная host-type compatibility |
| Universality and adaptability | profiles/defaults separation, generic analyzers, extra preservation | multi-spec landing comparison | Aurora `3/3`, Helios `2/2`, frozen black-box `12/12` | corpus синтетический/зафиксированный, не 12 real providers |
| Unsupported/ambiguous behavior | `REVIEW_REQUIRED`, `UNKNOWN`, blocking generation gate | Review and blocked Generate page | mutation and black-box safety checks | новые feature classes требуют отдельного evidence и rule |
| Documentation, fixtures, ease of use | updater-managed docs, generated artifacts, CLI/Web | README, Demo, integration docs | updater idempotency, RSpec, CI | оценка judge presentation itself не является runtime fact |

## Organizer contract alignment evidence

Эта матрица дополнительно проверяет не только наличие analyzer/runtime, но и
границу organizer contract:

| Contract area | Current evidence | Status |
|---|---|---|
| Host operation и requisites | [`docs/ORGANIZER_CONTRACT.md`](../docs/ORGANIZER_CONTRACT.md), `space_payments_v1`, generated NovaPay `INTEGRATION.md` | PROVEN для текущего profile |
| `request_method` и provider HTTP | [`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md), Demo Workbench, generated endpoint section | PROVEN для зафиксированных fixtures |
| `success(result: { id: ... })` и persistence boundary | organizer contract document, generated integration docs, UI response preview | BOUNDED; production host persistence не заявляется |
| Status helpers и raw-body HMAC | generated status/callback sections, Demo Workbench, behavioral vectors | BOUNDED для NovaPay/Aurora/Helios fixtures |
| Unknown requisite safety | Review manifest, structured unresolved item и generation gate | PROVEN для проверенных safety cases |

Эта секция является traceability evidence, а не самостоятельным начислением
баллов. Полные ответы для jury собраны в [`docs/JURY_FAQ.md`](../docs/JURY_FAQ.md).

## Current proven boundary

В текущем checkout доказаны parsing, evidence-backed semantic mapping,
fail-closed Review, deterministic generation, generated Ruby syntax/contract,
localhost outbound HTTP E2E, multi-provider fixture shapes и cross-platform CI.

`TransportVerification` отдельно подтверждает:

```text
generated adapter
  → real localhost socket request
  → captured method/path/query/auth/body/content type
  → response parsing/status mapping
  → persisted runtime_transport evidence
```

Это не меняет claim boundary: external real provider sandbox и production host
acceptance остаются **NOT CLAIMED**.

## Не заявляется

- поддержка любого OpenAPI;
- 100% automatic integration;
- 37 реальных providers — это 37 mutation cases одного reference domain;
- real production `Space Payments BaseService` compatibility;
- live NovaPay/Aurora/Helios sandbox execution;
- наличие моделей машинного обучения, neural runtime или внешнего inference service.

## Historical scorecards

Старые scorecards и red-team документы сохраняются как история исследования.
Их числа могут относиться к предыдущему HEAD и не должны использоваться как
current acceptance metrics. Для текущих результатов используйте generated blocks
README/`docs/BENCHMARK.md` и итоговый
[`research/GOAL_6_5_RESULT.md`](GOAL_6_5_RESULT.md).
