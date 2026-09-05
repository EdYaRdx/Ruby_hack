# GOAL 5.6 — DEMO-GRADE UI/UX RESULT

Дата проверки: 2026-09-06

## Область изменений

Изменения ограничены presentation layer:

- lib/provider_compiler/web.rb — отдельный явный demo entry point для NovaPay spec-only;
- lib/provider_compiler/web_renderer.rb — human-first страницы и process-state navigation;
- web/public/app.css — визуальная иерархия, responsive layout, focus states;
- web/public/app.js — доступная upload feedback и безопасное copy feedback;
- spec/web_spec.rb — UI/UX и safety presentation regression coverage.

Analyzer semantics, decision thresholds, CaseDefaults, ground truth, benchmarks,
money/status/auth/webhook inference и generator semantics не изменялись.

## Homepage

| Проверка | Результат |
|---|---|
| Новый анализ OpenAPI объясняет spec-only режим | PASS |
| NovaPay spec-only demo виден отдельно | PASS |
| NovaPay resolved demo виден отдельно | PASS |
| Разница между knowledge modes объяснена | PASS |
| Review представлен как safety feature | PASS |
| Aurora, HeliosPay и ambiguous demo сохранены | PASS |

Один и тот же NovaPay теперь показывается в двух явно названных режимах:

- NovaPay — только OpenAPI → 10 из 14, 4 решения требуют Review;
- NovaPay — эталонный resolved сценарий → 14 из 14, готов к Preview/Generation.

## Analysis

| Проверка | Результат |
|---|---|
| Hero summary виден сразу | PASS |
| 10 из 14 и 4 review отображаются human-first | PASS |
| Дублирующие глобальные status pills удалены | PASS |
| Статусы не описываются как resolved до ACCEPT | PASS |
| Semantic areas отображаются отдельно | PASS |
| Technical evidence скрыта внутри details | PASS |
| EXTRA_OPERATION и /balance визуально сохранены отдельно | PASS |

## Review

Review стал focused workflow: один active decision, progress, очередь следующих
решений и автоматический переход к следующему unresolved вопросу после POST.

| Проверка | Результат |
|---|---|
| Known fact отдельно от proposal | PASS |
| Proposal отдельно от user choice | PASS |
| Critical unknown не preselect-ится | PASS |
| Money: minor/scale требуют явного выбора | PASS |
| Webhook: hex/base64 требуют явного выбора | PASS |
| Status candidates не считаются подтверждёнными | PASS |
| Field transform/factor не подставляются для unresolved mapping | PASS |
| Review не выглядит как application error | PASS |

## Preview

| Проверка | Результат |
|---|---|
| Blocked Preview перечисляет unresolved decisions | PASS |
| Blocked Preview содержит CTA в Review | PASS |
| Request показывает Space Payments → transformation → Provider API | PASS |
| Money transformation показывает major → minor и × 100 для resolved NovaPay | PASS |
| Response transformation показывает status/amount mapping | PASS |
| Webhook transformation показывает verification → mapping → action | PASS |
| Generic Preview не содержит NovaPay hardcode | PASS |

## Generation

| Проверка | Результат |
|---|---|
| Blocked state объяснён как expected Review state | PASS |
| Ready state показывает число артефактов | PASS |
| Основные артефакты отделены от advanced artifacts | PASS |
| NOT RUN не называется FAIL | PASS |
| Verification показывает реальные checks | PASS |

## Language and accessibility

- Основной пользовательский copy — русский.
- Technical identifiers сохранены: OpenAPI, Provider Blueprint, Review Manifest,
  Ruby, service.rb, create_request, fetch_status, process_callback,
  HMAC-SHA256, HTTP, JSON.
- Добавлены focus-visible, semantic buttons/links, input/select labels и
  текстовые статусы, не зависящие только от цвета.
- CSS не добавляет framework и содержит responsive breakpoints для узких экранов.
- Long paths/code остаются внутри scrollable viewers; overflow-x страницы скрыт.

## Browser audit

Проверены реальные UI flows:

1. homepage;
2. NovaPay spec-only;
3. NovaPay resolved;
4. unresolved Review;
5. blocked Preview;
6. resolved Preview;
7. pre-generation Generation.

Проверенные свойства: CTA виден, sidebar показывает process state, Review readable,
long paths не ломают grid, critical selects имеют placeholder, Preview объясняет
трансформацию, Generation объясняет readiness.

## Regression

| Проверка | Результат |
|---|---|
| Full RSpec | 82 examples, 0 failures |
| Reference benchmark | 37/37 |
| NovaPay spec-only | 10/14 ACCEPT, 4/14 REVIEW_REQUIRED |
| NovaPay mutation | 74/98 decisions |
| Aurora | 12/14 pure generic → 14/14 resolved, 4/4 vectors |
| HeliosPay | 11/13 spec-only → 13/13 resolved, 4/4 vectors |
| Critical false ACCEPTs | 0 |
| Unsafe generation attempts | 0 |
| ruby bin/audit_ruby_share | PASS, Ruby share 89.2% production / 91.5% with tests |
| bin/update_docs twice | PASS / idempotent |
| bin/update_examples twice | PASS / idempotent |
| git diff --check | PASS |

## Backend freeze

- Semantic backend changes: NONE.
- Analyzer semantics changed: NO.
- CaseDefaults semantics changed: NO.
- Ground truth changed: NO.
- Benchmark ground truth changed: NO.

The only backend-adjacent change is the Web demo registry entry
novapay_spec_only, which selects the existing official fixture with
empty_case_defaults.yml and case_pack: nil; it does not alter analyzer
behavior or canonical semantics.

## Final

- UI explains spec-only versus resolved: YES
- Review is understandable: YES
- Demo-ready for checkpoint: YES
- Backend still frozen: YES
- GOAL 5.6 complete locally: YES
- Remote CI: commit pushed to `origin/main`; GitHub Actions status is not observable from this environment (`Page not found`)
