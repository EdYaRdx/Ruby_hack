# Исторический аудит текущей architecture

> Исторический snapshot до реализации. Этот audit фиксирует состояние
> репозитория до реализации production vertical slice. Текущая implementation
> находится в `lib/`, `bin/`, `profiles/`, `fixtures/` и `spec/`; актуальная
> GitHub-facing документация находится в [`docs/`](../docs/).

## Scope и качество evidence

Проверенные inputs:

- официальный `provider_api.yaml` (OpenAPI 3.0.3; актуальный SHA-256 записан в
  `REFERENCE_GROUND_TRUTH.md`);
- `описание.docx`, описание case и rubric;
- предыдущие research files этого репозитория;
- organizer Q&A из текущего review request.

На момент этого audit репозиторий содержал research documents и benchmark
policy data, но не содержал production parser, analyzer, generator, CLI, Ruby
test suite или реальный `BaseService`. Поэтому «current coverage» означал
architectural coverage, а не реализованное behavior.

## Что было сильным

1. Он правильно выделяет semantic gap между структурой OpenAPI и бизнес-ограничениями платежей.
2. Он разделяет facts и inference и выносит semantic logic за пределы templates.
3. Он считает money, terminal statuses, idempotency/retry и webhook crypto safety-critical.
4. Он сохраняет extra endpoints, например `/balance`, вместо принудительного включения их в host contract из четырёх методов.
5. Он использует одну Blueprint, предотвращая drift между service/docs/fixtures.
6. Он соблюдает ограничения no-neural и Ruby-majority.
7. Список mutations полезен как будущий regression corpus.

## Что не было доказано

### 1. Overclaim benchmark

Предыдущий `aggregate.ps1` вручную назначал outcome map для каждого approach. Он
агрегировал labels, но не менял YAML, не запускал Ruby implementation и не
наблюдал decisions analyzer. `100% ACCEPT precision`, `89.2% safe coverage` и
zero false accepts были свойствами policy-emulator table, а не измеренной
производительностью алгоритма.

### 2. Circular validation

Выбранный hybrid profile был определён так, чтобы совпасть с теми же expected
labels, которыми затем его оценивали. Для проектирования test это полезно, но
как proof является circular. Настоящий benchmark должен сначала зафиксировать
expected labels, затем выполнить real implementation как black box. Для выбора
threshold нужен также held-out set, а не только mutations, использованные для
подбора threshold.

### 3. Thresholds — это hypotheses

`score >= 8` и `top1-top2 margin >= 2` были предложены, но не calibrated. Их можно
сохранить как initial defaults, однако implementation должна показать threshold
sweep и выбрать точку, сохраняющую zero critical false accepts. Score — не
probability.

### 4. Contract uncertainty

Пример в case description показывает имена методов и illustrative helpers, но не
полный production API. Предыдущие материалы иногда говорили так, будто
`approve_operation`, `reject_operation`, `success`, `failure` и `client`
считались гарантированными. До представления в profile/stub это только
`CASE_ASSUMPTION`.

### 5. Q&A facts смешаны с YAML facts

NovaPay kopecks, conditional `bank_code` и exact signature encoding являются
валидным case ground truth после Q&A, но не все они независимо machine-readable
facts в YAML. Их provenance должна быть `CASE_DEFAULT`; generic providers без
таких declarations не должны их наследовать.

### 6. OSS choice не выполнен

Репозиторий рекомендовал libraries, но в тогдашнем окружении не было Ruby и
установленного bundle. Compatibility, ref behavior, version pinning и runtime
performance не проверялись на real implementation.

### 7. Score estimate — не score

`EXPECTED_SCORE.md` — planning model. Поскольку implementation отсутствовала,
technical score следовало читать как potential coverage, а не как current points.

## Отсутствующие части architecture

| Gap | Consequence | Required correction |
|---|---|---|
| BaseService contract boundary | generator can target wrong helpers/signatures | `BaseServiceProfile` + explicit stub |
| review-before-resolution | unresolved inference can look accepted | `Candidate` and `Review Manifest` before Blueprint |
| precedence/freshness | stale override can silently win | fingerprinted, scoped override policy |
| actual benchmark runner | metrics are circular/policy-only | mutate specs, run real Ruby, compare labels |
| schema for review decisions | UI/file/CLI may diverge | versioned review manifest + override schema |
| independent holdout | threshold overfits 37 labels | unseen fixtures and held-out mutations |
| output status contract | unclear whether review can generate | default: no production artifact until resolved |

## Вывод audit

Тогдашнюю architecture следовало изменить, а не отвергнуть. Её центральная идея
верна, но ей нужна более узкая и честная implementation boundary. Freeze следует
делать только после того, как четыре correction выше попадут в новые artifacts и
первый real vertical slice пройдёт profile/stub contract.
