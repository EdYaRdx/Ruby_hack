# GOAL 5.5 — correctness hotfix result

## ANALYZE

До исправления `CLI.run("analyze")` напрямую вызывал
`DeterministicGenerator#generate`. На unresolved spec это приводило к runtime
generation path и падению при попытке вычислить smoke amount:
`BigDecimal("")`. Analysis artifacts при этом не создавались.

Теперь `analyze` использует отдельный `AnalysisArtifactWriter` и записывает
только:

- `provider_blueprint.json`;
- `review_manifest.json`.

Команда возвращает success как analysis command даже при `REVIEW_REQUIRED` /
blocking, а stdout явно содержит `decision`, `blocking` и `generation_ready`.
Для unresolved NovaPay spec-only:

- analyze exit code: `0`;
- decision: `REVIEW_REQUIRED`;
- blocking: `3`;
- generation_ready: `false`;
- runtime artifacts: **NONE**.

Из существующего output каталога удаляются только известные generated runtime
files; остальные пользовательские файлы сохраняются.

## GENERATE

`generate` сохраняет validation-before-generation:

```text
Pipeline -> Blueprint validation -> DeterministicGenerator
```

Unresolved generation завершается non-zero до вызова runtime generator. В
проверке с заранее существующим `keep.txt` пользовательский файл сохранён,
runtime artifacts не появились. Resolved NovaPay `generate` и `verify` прошли.

## BASE SERVICE CONTRACT

Generated `check_conditions` теперь вызывает `super(operation, request_method)`
до provider-specific early return:

1. parent success + create — PASS;
2. parent failure + create — propagated, PASS;
3. parent success + non-create — `super` вызван, provider create constraints не
   применены, PASS;
4. parent failure + non-create — propagated, PASS.

Hash failure contract не расширялся: сохранён фактически используемый
organizer harness contract, а regression test явно покрывает success/failure.

## GENERATED DOCUMENTATION

`INTEGRATION.md` теперь содержит только Blueprint-driven sections:

- `## Маппинг статусов` — provider status → Space Payments status;
- `## ProviderGateway / конфигурация` — generated service class, BaseService,
  environment URLs, auth strategy, key/header, webhook secret input,
  idempotency spec fact vs adapter policy и canonical operations.

Проверено на фактических NovaPay Blueprint pairs. Provider-specific literals в
generator template отсутствуют. Production ProviderGateway framework syntax не
придумывается; документация описывает параметры, которые host application
должно адаптировать к своему gateway.

## WORDING

HeliosPay уже описан как независимая synthetic/third-provider validation; claim
`blind third-provider validation` в текущих judge-facing документах отсутствует.
Новых изменений wording не потребовалось.

## REGRESSION

| Проверка | Результат |
|---|---:|
| RSpec | 80 examples, 0 failures |
| Reference mutation benchmark | 37/37 |
| NovaPay official spec-only | 10/14 ACCEPT, 4/14 REVIEW_REQUIRED, 71.4% |
| NovaPay mutation lane | 74/98, 75.5% |
| Aurora | 12/14 spec-only, 14/14 resolved, vectors 4/4 |
| HeliosPay | 11/13 spec-only, 13/13 resolved, vectors 4/4 |
| Critical false ACCEPTs | 0 |
| Unsafe generation attempts | 0 |
| Ruby share | 92.8% production-only, 94.4% production + tests |
| Official NovaPay SHA | `415F50EE36FB331DFAB49CEED0E8ED3B0EBE16053D7E00DBABD32282F4396551` |
| `update_docs` idempotency | PASS |
| `update_examples` idempotency | PASS |
| `git diff --check` | PASS |

## REMOTE CI

Hotfix commit: `e3b69ff` (`fix: harden analysis and generated contract checks`).

GitHub Actions [run 33993792204](https://github.com/EdYaRdx/Ruby_hack/actions/runs/33993792204):
`completed / success`.

Все обязательные steps PASS: checkout, Ruby 3.3 setup, bundle install, RSpec,
syntax, Ruby share, reference benchmark, NovaPay spec-only, Aurora, HeliosPay,
`update_docs`, `update_examples` и reproducibility/repository hygiene.

## BACKEND FREEZE

- Analyzer semantics changed: **NO**.
- Benchmark ground truth changed: **NO**.
- Decision thresholds, defaults, money/status/auth/webhook inference: **NO**.
- Web UI design and architecture layers: **NO**.
- New feature scope: **NONE**; только surgical correctness, generated docs и
  targeted regression tests.
- Official SHA: unchanged.
- Correctness ready: **YES**.
- Ready for UI-only GOAL: **YES**, after the documentation commit passes the
  same CI workflow.
