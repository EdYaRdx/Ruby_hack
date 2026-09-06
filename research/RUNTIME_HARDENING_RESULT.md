# Runtime hardening result

GOAL 6.1 runtime scope исправил только подтверждённые P0/P1 и baseline
failures. Pipeline `Facts IR -> Evidence -> Review Manifest -> Blueprint ->
Generator` сохранён.

## Confirmed fixes

1. Generated webhook handler теперь fail-closed при противоречии `event` и
   provider `status`; approve/reject action не вызывается.
2. Runtime failure paths используют один profile-driven `host_failure` helper и
   объявленный `failure_contract.arguments`.
3. `BaseService` pre-check понимает Hash failure и result objects с `failed?`/
   `ok?`; constructor contract не расширялся непроверенным `super`.
4. Transport сохраняет canonical request `{method, url, headers, query, body}`.
   GET/POST fallback больше не теряет query: параметры сериализуются в URL.
5. Hash response, object response (`status/body/headers`) и JSON string body
   нормализуются одинаково; malformed non-empty JSON возвращает diagnostic.
6. HTTP 204 без body считается success только для documented success status.
7. HTTP error без `error.code` не выбирает первый provider code; сохраняются
   HTTP category и `Retry-After`.
8. Path parameters URL-экранируются.
9. Fallback-generated idempotency key явно остаётся process-local; durable retry
   safety не заявляется.

## Host boundary assumptions

| Boundary | Evidence / assumption |
|---|---|
| FACT_FROM_CASE | Case description подтверждает conceptual methods `check_conditions`, `create_request`, `process_callback`, `fetch_status` и helpers `success`, `failure`, `approve_operation`, `reject_operation`. |
| HOST_PROFILE_ASSUMPTION | Profile объявляет `call_super`, `failure_contract.arguments: [status, code, message]`, validation status/code и callback actions. |
| TEST_HARNESS_ASSUMPTION | Repository harnesses используют Hash results и test-only `BaseService`; это не production class. |
| GENERATED_RUNTIME_ASSUMPTION | Adapter принимает `api_key`, optional webhook secret/client и canonical transport interface; concrete organizer constructor/client signature остаётся внешним контрактом. |

Неизвестный production `BaseService` не объявлен в checkout, поэтому runtime
совместимость с ним не overclaimed.

## Runtime evidence

`spec/runtime_hardening_spec.rb`: 6 examples, включая:

- реальный localhost WEBrick → generated adapter → Net::HTTP → JSON response;
- query auth и header auth;
- POST create, GET status, request JSON, 202/200 responses;
- documented 204 without body;
- 429 + `Retry-After`;
- GET/POST fallback query;
- response object;
- webhook contradiction;
- validation/missing id/malformed response/unknown status refusal paths.

Все 6 examples прошли. Vectors в
`research/black_box_v1/runtime_vectors.yml` написаны независимо от Blueprint.

