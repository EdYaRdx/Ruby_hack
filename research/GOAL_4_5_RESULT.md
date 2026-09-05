# GOAL 4.5 — Explainability UX Polish

> HISTORICAL SNAPSHOT — superseded by GOAL 5 and GOAL 5.1. This document records the former GOAL 4.5 checkpoint and is not the current product behavior or current metric source. See [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md), [docs/BENCHMARK.md](../docs/BENCHMARK.md), [GOAL_5_RESULT.md](GOAL_5_RESULT.md), and [NOVAPAY_SPEC_ONLY_BASELINE.md](NOVAPAY_SPEC_ONLY_BASELINE.md).

## GOAL 4.5 RESULT

Готово. Web Workbench получил единый трёхуровневый explainability UX без
изменения backend semantics:

1. **Результат** — короткое human-readable решение рядом с фактом.
2. **Основания решения** — явный keyboard-accessible inline control с объяснением,
   human labels, техническими source IDs и конфликтами.
3. **Технические подробности** — отдельный collapsed блок с Decision ID,
   Provenance, OpenAPI pointer и raw candidate/rationale/evidence.

## Analysis

- Маленькие primary-ссылки `Почему?` удалены.
- Operations используют `Подробнее`; внутри показываются `Определено как`,
  основания и evidence.
- Money, Statuses и Webhook используют единый control `ⓘ Основания решения`.
- Money объясняется как `major RUB → minor/копейки ×100` с раздельными
  источниками профиля Space Payments, OpenAPI и case profile.
- В Statuses отдельно сохранены `Показать все` и `Основания решения`.
- Extra operations остаются видимыми и маркируются как `EXTRA_OPERATION`.

## Review

- Сохранены `Что известно?`, `Что нужно подтвердить?`, `Почему это важно?` и
  `Предлагаемый вариант`.
- `Почему это важно?` показывает business impact отдельно от evidence.
- Добавлен отдельный control `Основания предложения`.
- Status review явно объясняет provider → Space Payments mapping для
  `fetch_status` и webhook.
- Raw JSON не показывается по умолчанию; technical details остаются collapsed.

## Happy-path Review

Для resolved NovaPay показываются:

- `Проверка не требуется`;
- `Перейти к предпросмотру` как primary CTA;
- `Посмотреть принятые решения` как secondary CTA.

Бесполезная кнопка `Открыть проверку` отсутствует. Preview и Generation
сохранили прежние layout и runtime semantics.

## Regression evidence

| Check | Result |
| --- | --- |
| Full RSpec | `63 examples, 0 failures` |
| Web UX spec | `17 examples, 0 failures` |
| Web NovaPay | PASS — Analysis explainability and resolved Review happy path |
| Web Ambiguous | PASS — Review remains fail-closed; resolution path still unlocks runtime |
| NovaPay CLI decisions | `accepted=14`, `review_required=0`, `blocking=0` |
| NovaPay generated syntax + contract smoke | PASS |
| Preview | PASS — `1500.50 → 150050` |
| Generation | PASS |
| Mutation benchmark | `37/37`, critical false ACCEPTs `0` |
| Critical false ACCEPTs | `0` |
| Aurora semantic comparator | `3/3`, critical false ACCEPTs `0` |
| Aurora behavioral vectors | `4/4` |
| Official provider SHA | unchanged: `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551` |

## Scope and architecture impact

**Backend semantic changes: NONE.** Изменения ограничены renderer, CSS и web
regression tests. Analyzer, Review Manifest, Provider Blueprint, generator,
runtime mappings и benchmark semantics не менялись.

Known UX limitations:

- explainability реализована native HTML `<details>`, без отдельного frontend
  framework;
- resolution state остаётся workspace/in-memory scoped;
- live provider calls по-прежнему находятся вне demo workbench.

## Final status

- `EXPLAINABILITY UX READY: YES`
- `DEMO READY: YES`

BACKEND BENCHMARK VALIDATED

GO for GOAL 4.
