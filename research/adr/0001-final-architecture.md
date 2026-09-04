# ADR-0001: Evidence-gated semantic Blueprint architecture

- Статус: принято для планирования MVP
- Дата: 2026-09-03
- Область: только research Hack.Genesis 2026

## Контекст

Input — это OpenAPI description provider-а. Output должен быть Ruby service,
совместимый с `Provider::BaseService`, integration documentation, fixtures и
демонстрируемым CLI. Reference document содержит payout, status, cancel, webhook
и balance operations, а также critical details: kopecks, idempotency,
Retry-After и HMAC-SHA256. Некоторые другие meanings только подразумеваются
именами или prose.

Direct template generation быстра, но скрывает guesses. Structural IR убирает
parser noise, но всё ещё не предоставляет безопасного места для critical
semantic uncertainty.

## Решение

Решение:

```text
OpenAPI
  -> validated Structural IR
  -> independent payment-aware analyzers
  -> evidence ledger + decision gate
  -> Provider Blueprint
  -> deterministic projections
       -> Ruby service
       -> INTEGRATION.md
       -> fixtures.json
       -> diagnostics
  -> ruby -c + schema/contract tests
```

Semantic approach — rules + limited aliases + schema/structural evidence +
explainable score/margin + abstention. `ACCEPT` разрешён только при прохождении
critical gates. `REVIEW_REQUIRED` и `UNKNOWN` — first-class outcomes, а не
ошибки, скрытые от user.

## Граница Blueprint

Blueprint владеет provider metadata, servers, auth, canonical operation
bindings, endpoint refs, field pointers, money transformation, status/error maps,
idempotency и webhook policy, conditional fields, extra operations, evidence,
decision, warnings и unknowns. Templates не должны читать OpenAPI descriptions,
чтобы угадывать semantics.

## Последствия

Положительные:

- один source of truth генерирует три связанных artifacts и diagnostics;
- parser, semantic и generator tests независимы;
- mutations показывают устойчивость к изменениям naming/layout;
- critical assumptions остаются видимыми и доступными для review;
- добавление нового analyzer не требует переписывать templates.

Издержки:

- кода больше, чем при direct templates;
- threshold calibration и evidence schema нужно спроектировать заранее;
- некоторые необычные, но valid providers получают review/unknown вместо
  automatic output;
- для generation QA всё ещё нужен final Ruby runtime/host contract.

## Отклонённые альтернативы

1. **Direct OpenAPI -> ERB.** Отклонено из-за скрытой semantic logic и высокого
   hardcode risk.
2. **IR -> generator without analyzers.** Отклонено: такой подход не может
   корректно моделировать unknown money units, retry safety и uncertainty
   terminal status.
3. **Fuzzy/BM25/graph-first semantics.** Отклонено: benchmark evidence не
   оправдывает false-accept risk и стоимость реализации.
4. **Web UI before CLI.** Отклонено: добавляет demo surface, но не correctness
   evidence.

## Обязательства по verification

Implementation должна запускать 37-case mutation benchmark, golden NovaPay tests,
generated Ruby syntax checks и fixtures validation. Этот ADR не разрешает
запускать production implementation в рамках текущей research task.
