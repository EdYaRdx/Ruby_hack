# GOAL 6.5 — Multi-spec universality and outbound HTTP evidence

Дата: 2026-09-06
Исходный checkpoint: `6e0f534`

## Итог

GOAL 6.5 выполнен в заявленном scope. Исправления закрывают видимость
multi-spec evidence и независимую проверку outbound HTTP. Архитектура не
перепроектировалась: verifier потребляет сгенерированный Blueprint/adapter,
readiness и UI только проецируют фактический результат.

## Multi-spec evidence

Landing page показывает один сравнимый блок для трёх независимых fixture/spec
пар и CTA для произвольной загрузки:

| Provider | Фактические различия, видимые evaluator |
|---|---|
| NovaPay | API key в header, flat `amount`, `POST /payouts`, `GET /payouts/{payout_id}` |
| Aurora | Bearer в header, nested `money.value`, `POST /transfers`, `POST /notifications` |
| HeliosPay | API key в query, nested `payment.amount`, `POST /funds`, HTTP `202`, `Retry-After` |
| Arbitrary upload | обычный upload/analyze path без автоматической case-pack подстановки |

Rows строятся из текущих `Pipeline`/Blueprint данных. Generic analyzer не
содержит ветвления по имени provider. Независимые semantic и behavioral
проверки существующих Aurora/Helios lanes не заменены сравнением decision.

## Outbound HTTP evidence

`TransportVerification` выполняет generated adapter против ephemeral localhost
provider через реальный `Net::HTTP` socket и сохраняет результат в
`runtime_transport`:

- transport implemented: YES;
- executable local transport verification: YES;
- external provider sandbox call: NO — endpoint/credentials не предоставлены и
  внешний вызов намеренно не выполняется.

Проверяются method/path/query/auth/body/JSON content type для create, method/path
с подстановкой идентификатора/auth для status, response parsing и canonical
status mapping. Чувствительные заголовки и ephemeral port редактируются в
persisted evidence. Generate UI, `integration_readiness.json` и
`INTEGRATION_READINESS.md` показывают один и тот же фактический результат.

## Regression matrix

| Проверка | Результат |
|---|---:|
| `bundle exec rspec` | 111 examples, 0 failures, 1 expected pending (Windows symlink) |
| Mutation benchmark | 37/37; semantic ACCEPT accuracy 100%; critical false ACCEPT 0 |
| NovaPay spec-only | 7/7; safe decision coverage 100%; unsafe generation 0 |
| Aurora levels | 3/3; decision accuracy 100%; semantic accuracy 100%; safe coverage 100% |
| HeliosPay levels | 2/2; critical false ACCEPT 0 |
| Frozen black-box | 12/12; critical false ACCEPT 0; unsafe generation 0 |
| `ruby bin/update_docs` | PASS, повторный запуск идемпотентен |
| `ruby bin/update_examples` | PASS; generated NovaPay transport PASS |
| `ruby bin/audit_ruby_share` | PASS; production Ruby share 90.6% |
| `git diff --check` | PASS |

## Architecture impact

**No architecture redesign.** Изменены только verification boundary, persisted
readiness projection, evaluator-facing UI comparison, tests and documentation.
Facts IR, analyzer precedence, Blueprint semantics, generator mapping, Review
fail-closed behavior и BaseService contract не менялись.

## Final status before push

- MULTI-SPEC EVIDENCE VISIBLE: YES
- OUTBOUND HTTP EVIDENCE VISIBLE: YES
- REAL PROVIDER LIVE INTEGRATION PROVEN: NO
- CRITICAL FALSE ACCEPTS: 0
- UNSAFE GENERATION ATTEMPTS: 0
- ARCHITECTURE REDESIGN: NO
- BACKEND REGRESSION: GREEN
