# GOAL 6.7 — Organizer Contract Alignment

Дата проверки: 2026-09-06

## Итог

Сгенерированный adapter и host boundary приведены в соответствие с
организаторскими уточнениями. Semantic compiler, порядок стадий и модель
`Facts IR → Evidence → Review Manifest → Provider Blueprint → Generator` не
перепроектированы.

Проверенный NovaPay Blueprint:

- decision: `ACCEPT`;
- `REVIEW_REQUIRED`: `0`;
- `BLOCKING`: `0`;
- Ruby syntax, CLI `generate` и CLI `verify`: `PASS`;
- fingerprint официального входа: `sha256:2b6ad1db111691c80f3b098d76d69896fc88c7b0859f9a17af725325dbbbda77`;
- SHA-256 официального `provider_api.yaml`: `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551`.

## Источники истины

1. Organizer Q&A из GOAL 6.7 — источник host/BaseService contract.
2. `C:\Users\Эдуард\Downloads\provider_api.yaml` — официальный provider
   документ.
3. `fixtures/novapay_provider_api.yaml` — repository copy официального
   документа; её SHA-256 совпадает с входным файлом из Downloads.
4. `profiles/space_payments_v1.yml` — только явные host/profile правила, не
   замена provider evidence.

## Исправленные противоречия

| Область | Уточнённый контракт | Реализация и evidence |
|---|---|---|
| Host operation | Доступны `operation.id`, `operation.amount`, `operation.payout_requisite` (hash/JSONB) | Profile `host_operation` и `host_projection`; NovaPay `operation.id` проецируется в provider `external_id`, requisite — в provider `recipient` |
| Money | Host/canonical: major RUB; provider: minor/kopecks | Provider spec description сообщает kopecks; profile canonical amount сообщает major RUB; `request_conversion.direction=major_to_minor`, factor `100`; обратная конверсия `0.01` |
| Idempotency | OpenAPI `Idempotency-Key` имеет `required: false` | `spec_required=false`, evidence=`SPEC_FACT`; optional send behavior (`if_available`/`always`) хранится отдельно как `ADAPTER_POLICY` |
| Fetch operation | Official operationId — `getPayoutStatus` | Blueprint binding: `GET /payouts/{payout_id}`, operationId `getPayoutStatus`, canonical `fetch_status` |
| Sandbox | Используется URL из official `servers` | `https://api.sandbox.novapay.example/v1`; runtime override остаётся через `NOVAPAY_BASE_URL` |
| `/balance` | Не является обязательной BaseService operation без profile rule | Сохранён как `EXTRA_OPERATION`, `preserved=true`, `blocking=false`; canonical `operations` его не содержит |
| Fingerprint | Учитывается resolved local input closure | `fingerprint_inputs` включает root document, локальные `$ref`, `resolved_local_ref_closure`, `resolved_files` и resolver policy |
| Create result | Provider id не хранится service-owned; он возвращается платформе | Generated adapter вызывает `success(result: { id: provider_id })`; service не содержит `@provider_operation_id` persistence |
| Failure | Domain/platform code первым, i18n key вторым; provider detail — metadata | Generated adapter вызывает `failure(code, i18n_key)` и сохраняет `error`, `error_code`, HTTP status, retry metadata отдельно |
| `amount_limit_exceeded` | Ошибка лимита/валидации операции, не daily limit и не operator review | Provider code mapping: `unprocessable_entity` + `provider.amount_limit_exceeded`; provider code/message остаются metadata |
| Status actions | Terminal status вызывает host helper; in-progress — нет | `approved → approve_operation`, `rejected → reject_operation`, `in_progress → none`; service не сохраняет status |
| Webhook | Parsed payload и raw signed body — разные inputs | HMAC проверяется по exact `raw_body`; parsed payload используется после проверки; missing raw/signature/invalid signature fail closed |
| Unknown requisite | Нельзя угадывать отсутствующий host mapping | `HostProjectionAnalyzer` создаёт `REVIEW_REQUIRED/BLOCKING`, сохраняет provider field и TODO; unsafe `service.rb` generation не выполняется |

## Host projection

Внутренний canonical alias `operation.recipient` сохранён там, где его требует
существующая semantic model. Для host boundary добавлено data-driven projection:

```text
operation.id              → request.external_id
operation.payout_requisite → request.recipient
operation.amount          → request.amount × 100
```

Для NovaPay SBP branch provider-required `phone` и `bank_code` берутся из
`operation.payout_requisite.sbp`. Card branch требует явные `card_number` и
`phone` внутри `payout_requisite`; top-level `recipient_phone` не считается
гарантированным host field. Если provider schema требует поле, для которого
profile не объявил mapping, результатом является review/TODO, а не blind
access к hash key.

`request_method` теперь означает логический gateway/payment method (`sbp` или
`card`). HTTP verb создаваемого запроса остаётся свойством provider endpoint и
для NovaPay равен `POST`; значение `create` больше не используется как
логический host method.

## Безопасность генерации

`DeterministicGenerator` и CLI materialize review artifacts для unresolved
Blueprint, но не создают `service.rb`, `fixtures.json` или `contract_smoke.rb`.
Для `ACCEPT` pipeline validation и runtime verification остаются обязательными.
Web Workbench сохраняет тот же gate: preview/generate доступны только для
полностью разрешённого Blueprint.

## Regression evidence

Focused organizer-contract regression содержит 22 независимых примера и
проверяет host fields, money conversion, logical method, card/SBP projection,
result wrapper, terminal helpers, raw-body HMAC, failure mapping, idempotency
provenance, operationId, extras, no service-owned provider id и unknown requisite
safety.

Результаты локального прогона:

| Проверка | Результат |
|---|---:|
| Focused organizer contract | 22 examples, 0 failures |
| Full RSpec | 133 examples, 0 failures, 1 expected Windows pending |
| NovaPay generated syntax/smoke/localhost transport | PASS |
| CLI generate + verify | PASS |
| Mutation benchmark | 37/37 |
| Mutation decision accuracy | 100.0% |
| Mutation semantic ACCEPT accuracy | 100.0% |
| Operation / money / status / auth / webhook / idempotency / field semantic accuracy | 100.0% each |
| Mutation critical false ACCEPT | 0 |
| Mutation generation | 18/18 |
| Aurora resolution levels | 3/3 semantic pass |
| Aurora resolved behavioral vectors | 4/4 |

Expected pending — symlink traversal case — связан только с отсутствием
symlink support в текущем Windows test environment и не является failure.

## Влияние на архитектуру

### Что не изменилось

- нет нового runtime service, LLM, neural/embedding dependency или provider-
  specific hardcoded compiler branch;
- semantic analyzers по-прежнему читают spec/profile/defaults и формируют
  immutable facts/evidence/decisions;
- `Provider Blueprint` остаётся единственным входом генератора;
- не изменены границы review gate и deterministic generation для accepted input;
- `/balance` не расширяет canonical BaseService contract.

### Что изменилось локально

- профиль получил явное описание organizer host projection и result/failure
  contract;
- добавлена проверка обязательных provider requisite fields в существующем
  analyzer stage;
- generated adapter получил host projection, новый BaseService invocation
  contract и fail-closed review generation;
- Web Workbench preview использует тот же host projection, что и generated
  adapter;
- transport/test doubles обновлены с invented positional contract на organizer
  contract.

Это локальное расширение существующего Blueprint/profile boundary, а не смена
архитектуры. Поэтому итоговая классификация: semantic core не redesigned;
исправлены ground-truth/host-contract inconsistencies и их regression gates.

## Вывод

Organizer contract alignment подтверждён для NovaPay и regression-проверен на
Aurora/остальном существующем наборе. Доказательство относится к явно
проверенным mappings и fixture corpus; оно не утверждает production readiness
для произвольного provider без его evidence/profile resolution.
