# GOAL 4.4 — UX Simplification + Official NovaPay Upload Fix

> HISTORICAL SNAPSHOT — superseded by GOAL 5 and GOAL 5.1. This document records the former GOAL 4.4 checkpoint and is not the current product behavior or current metric source. See [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md), [docs/BENCHMARK.md](../docs/BENCHMARK.md), [GOAL_5_RESULT.md](GOAL_5_RESULT.md), and [NOVAPAY_SPEC_ONLY_BASELINE.md](NOVAPAY_SPEC_ONLY_BASELINE.md).

## GOAL 4.4 RESULT

Готово. Web Workbench сохраняет существующую semantic pipeline и safety gate,
а обычный пользователь получает последовательность из пяти шагов:

`Спецификация → Анализ → Проверка → Предпросмотр → Генерация`.

## ROOT CAUSE

Проверка demo, CLI и ручной загрузки не выявила расхождения в semantic
Blueprint для официального NovaPay. Все три входа используют один и тот же
официальный документ; различие полного CLI fingerprint связано с именем
локального root-файла, тогда как content SHA одинаков.

Реальная UX-проблема была в другом: case association не была явно показана как
проверенная content-identity операция, Review UI не имел рабочего resolution
POST-пути и показывал disabled-представление вместо человеческих вопросов.

## Demo / manual inputs

| Input | Result |
| --- | --- |
| canonical NovaPay demo | NovaPay case pack |
| official upload as `foo.yaml` | тот же NovaPay case pack |
| official local SHA | `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551` |
| meaningful spec change | no case pack, empty defaults, fail-closed |

Case pack выбирается по SHA содержимого, а не по имени файла. Неизвестный
provider остаётся evidence-only: без trusted defaults он не получает NovaPay
business assumptions и не генерирует adapter.

## Official NovaPay verification

- summary: `accepted=14`, `review_required=0`, `blocking=0`;
- decision: `ACCEPT`;
- `create_request`: `POST /payouts`;
- `fetch_status`: `GET /payouts/{payout_id}`;
- operationId status: `getPayoutStatus`;
- host money: major RUB;
- provider money: minor/kopecks, scale `100`, request factor `100`;
- host money evidence: `BASE_SERVICE_PROFILE`;
- provider money evidence: specification + case defaults;
- idempotency: `Idempotency-Key`, OpenAPI `required=false`;
- adapter policy remains separate: `if_available`, provenance `ADAPTER_POLICY`;
- sandbox: `https://api.sandbox.novapay.example/v1`;
- `/balance`: preserved as non-blocking `EXTRA_OPERATION`;
- webhook: `POST /webhooks/payout`, `X-NovaPay-Signature`, HMAC-SHA256,
  raw body, hex.

Demo and manual upload produce equal Blueprint and Review Manifest. A renamed
official file is recognized; a meaningful content change is not.

## UX result

- Upload: «Новая интеграция», OpenAPI YAML/JSON drop zone and local processing.
- Analysis: «Что система поняла?» with concise cards for operations, auth,
  money, statuses, webhook, idempotency, fields, constraints and API errors.
- Extra endpoints are labelled «Дополнительная операция» with technical
  `EXTRA_OPERATION`.
- Review shows only unresolved decisions and presents human questions; raw JSON,
  IDs, provenance and evidence are under «Технические подробности».
- Human resolutions are workspace-scoped, merged into existing case-default
  overrides, and re-analyze the Blueprint after every confirmation.
- `REVIEW_REQUIRED` keeps the page in review state; `BLOCKING` is shown as
  «БЛОКИРУЕТ ГЕНЕРАЦИЮ»; `UNKNOWN` remains fail-closed; `READY` is shown only
  after unresolved decisions are gone.
- Preview and generation are locked until all unresolved/blocking decisions are
  resolved. Request, response and webhook previews use the generated runtime
  service.

## Regression evidence

| Check | Result |
| --- | --- |
| full RSpec | `63 examples, 0 failures` |
| web spec | `17 examples, 0 failures` |
| CLI NovaPay analyze | `14/0/0` |
| CLI generated syntax + smoke | PASS |
| mutation benchmark | `37/37`, semantic `100%`, critical false ACCEPT `0` |
| Aurora semantic comparator | `3/3`, semantic `100%`, critical false ACCEPT `0` |
| Aurora behavioral vectors | `4/4` |
| official SHA invariant | PASS |
| `update_examples` idempotence | PASS |
| `update_docs` idempotence | PASS |
| real WEBrick smoke | health 200, workbench 200, demo 303 |

## Backend impact

Architecture is preserved. Changes are limited to the web/workspace integration
layer, human resolution plumbing, explicit evidence provenance for confirmed
resolutions, a fail-closed runtime gate, and regression fixtures/tests. Generic
analyzer rules do not contain a NovaPay-specific branch; provider-specific
recognition is an explicit content-identity case-pack registry boundary.

## Known limitations

- Workspace resolutions are in-memory and session/workspace-scoped; there is no
  database persistence yet.
- Live provider calls are outside this demo; previews use deterministic fixtures
  and the generated runtime service.
- Automatic trusted defaults apply only to registered exact content identities;
  unknown or materially changed specifications require evidence or human review.

## Final verdict

BACKEND BENCHMARK VALIDATED

GO for GOAL 4.
