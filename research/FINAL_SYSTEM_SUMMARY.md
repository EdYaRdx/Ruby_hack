# Итоговое описание системы

Дата review: 2026-09-03

## Вердикт

**CHANGE.** Предыдущая идея `IR -> analyzers -> evidence -> Blueprint ->
generator` является правильным ядром, но её нельзя заморозить в текущем виде.
Нужны четыре точных изменения:

1. вынести неизвестный production-контракт в `BaseServiceProfile`;
2. разделить `Candidate/Review Manifest` и resolved `Provider Blueprint`;
3. сделать overrides scoped + fingerprinted, с блокировкой stale/conflicts;
4. заменить claim «benchmark доказал качество» на реальный mutate -> run Ruby
   implementation -> compare benchmark.

Итоговая форма — **profiled, evidence-gated integration compiler** с file-based
human review и verification workspace.

## Независимый выбор

Если начать с нуля, я бы выбрал не универсальный OpenAPI SDK generator и не
magic semantic mapper, а маленький компилятор адаптеров:

```text
OpenAPI/YAML
  -> validated document + source fingerprint
  -> facts-only Structural IR
  -> candidate analyzers + evidence
  -> Review Manifest
  -> scoped human decisions / overrides
  -> validated Provider Blueprint v1
  -> deterministic Ruby + docs + fixtures
  -> isolated BaseServiceStub/Profile verification
```

Это совпадает с прежним направлением, но не с прежним scope: Human Review Center
в MVP — CLI и YAML/JSON overrides, а не Web UI; reusable rules — только
ограниченный формат, а не knowledge platform.

## Какую задачу решает продукт

Space Payments вручную тратит 2–5 дней на чтение provider API и написание Ruby
adapter. Продукт сокращает повторяющуюся работу: извлекает структурные факты,
предлагает mappings, явно показывает неоднозначности, после подтверждения
генерирует `service.rb`, `INTEGRATION.md`, `fixtures.json` и запускает проверки.

Он не переписывает внешний API и не обещает безнадзорную production-интеграцию.
Обещание должно быть уже: «получить проверяемую заготовку адаптера и список
решений, которые ещё должен подтвердить интегратор».

## Минимальный итоговый продукт

- Ruby CLI: `analyze`, `review`, `generate`, `verify`, `inspect`;
- parser adapter + OpenAPI validation + bounded `$ref` resolver;
- facts-only IR;
- independent analyzers for operation, field, money, status, auth,
  idempotency/retry, error, webhook and bounded conditional fields;
- `Review Manifest` with evidence, provenance, conflicts and blocking severity;
- generic `overrides.yml` keyed by source fingerprint and JSON pointer;
- `Provider Blueprint v1` as the only codegen/documentation source;
- deterministic output: Ruby service, integration guide, fixtures and readiness
  report;
- local `BaseServiceStub` and `BaseServiceProfile`, clearly not production code;
- real Ruby mutation runner and four test layers.

## Safety contract

Система может автоматически принимать structural facts и explicit provider
declarations. Она должна отправлять на review или блокировать отсутствующие либо
неоднозначные money units, terminal statuses, idempotency/retry semantics,
authentication и webhook cryptography. Нельзя молча превращать high-risk
heuristic в global rule.

Для NovaPay provider-side amount — minor RUB units (kopecks), а canonical Space
Payments `operation.amount` — major RUB; request conversion — `×100`, response
conversion — `/100`. Provider unit имеет отдельное provider-spec/Q&A evidence,
не смешанное с host-unit evidence. Q&A также предоставляет `CASE_DEFAULT` для
`bank_code` при `type=sbp` и HMAC-SHA256(raw body, secret), закодированный как
hex в `X-NovaPay-Signature`. Эти values должны сохранять provenance и не должны
представляться так, будто все получены структурно из YAML. `Idempotency-Key`
optional в spec; любое always-send behavior — `ADAPTER_POLICY`, а не
`SPEC_FACT`.

## Статус evidence для существующего research

Предыдущий 37-mutation artifact полезен как label set и policy design. Это не
algorithm benchmark, поскольку outcome каждого approach вручную назначил автор
research. Его aggregate metrics нельзя использовать как proof semantic quality.
Новый implementation plan добавляет недостающий experiment:

```text
mutate actual OpenAPI
  -> run actual Ruby analyzer
  -> capture actual decision/evidence
  -> compare to frozen expected label
  -> run codegen and Ruby/fixture gates
```

## Решения по scope

| Decision | Final scope |
|---|---|
| Reusable rules | P1 format + low-risk contextual rules only; no automatic global promotion |
| Spec drift | P0 fingerprint over root plus resolved local-ref closure/stale override detection; P2 full diff |
| Web UI | cut from MVP; keep core UI-agnostic |
| Fuzzy/TF-IDF/BM25/graph | cut; fuzzy may rank review suggestions only later |
| BaseService | profile + stub now; real production adapter later when contract arrives |
| Network provider calls | fixtures/stubs for demo, no live financial calls |

## Критерии успеха до production

1. NovaPay golden fixture достигает case-default target с provenance.
2. Каждый generated artifact является projection одного Blueprint.
3. Реальный mutation benchmark: `ACCEPT` precision >=99% и zero critical false
   accepts для money, auth, idempotency/retry, statuses и webhook signature.
4. Каждый accepted service проходит `ruby -c`, stub contract, fixture validation
   и deterministic regeneration.
5. Любая отсутствующая деталь real BaseService видна как explicit profile gap, а
   не скрыта в generated code.
