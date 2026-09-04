# Текущая архитектура

Документ описывает реализованную архитектуру. Он намеренно стабилен и не
содержит benchmark totals.

## Граница системы

Компилятор принимает локальный OpenAPI-документ, profile host-контракта и case
defaults. Provider Blueprint создаётся только после анализа с учётом
доказательств. Ruby generator — детерминированная проекция этой Blueprint, а не
независимый источник семантики интеграции.

## Конвейер

```text
source files
  -> OpenAPILoader / OpenAPIValidator
  -> FactsBuilder (immutable provider facts)
  -> AnalyzerEngine (evidence, precedence, safety decisions)
  -> BlueprintBuilder + ReviewManifest
  -> BlueprintValidator
  -> DeterministicGenerator
  -> Verification (Ruby syntax + contract smoke)
```

Локальные references разрешаются до анализа. Source fingerprint включает корневой
документ, resolved local files и resolver policy, поэтому изменение closure
входных данных не может выглядеть как тот же самый источник провайдера.

## Семантические уровни

Facts фиксируют то, что сказано во входных данных. Evidence показывает, откуда
взято заключение. Analyzers интерпретируют facts в рамках выбранного
`BaseServiceProfile` и case defaults. Blueprint содержит выбранный mapping и
его decision state; Review Manifest сохраняет перечень решений для проверки.

Эти обязанности разделены между следующими частями реализации:

- `lib/provider_compiler/core.rb` — загрузка, references, facts и общие утилиты;
- `lib/provider_compiler/analysis.rb` — analyzers и правила precedence/safety;
- `lib/provider_compiler/profile.rb` — host-контракт и profile policy;
- `lib/provider_compiler/blueprint.rb` — каноническое представление и validation;
- `lib/provider_compiler/generation.rb` — deterministic output и verification;
- `lib/provider_compiler/application.rb` — orchestration CLI.

## Состояния безопасности

| Decision | Значение | Политика вывода |
|---|---|---|
| `ACCEPT` | Обязательная семантика разрешена с достаточными доказательствами | Blueprint можно генерировать и проверять |
| `REVIEW_REQUIRED` | Существенная неоднозначность остаётся | Сохранить evidence; при blocking-проблеме остановить generation |
| `UNKNOWN` | Поведение провайдера не поддержано или не восстановимо | Сохранить и сообщить item; не придумывать mapping |

Дополнительные endpoint-ы сохраняются как записи `EXTRA_OPERATION`. Они не
становятся canonical host methods, если profile явно их не связывает.

## Host-контракт и семантика провайдера

Profiles задают canonical host operation names, vocabulary статусов, callback
capabilities и representation assumptions. Provider mappings остаются в
Blueprint. Например, host amount в major units может требовать conversion в
provider minor units; такая conversion является first-class Blueprint value и
проверяется до generation.

Решения адаптера, например always-send idempotency header, представляются как
adapter policy. Их нельзя выдавать за provider specification facts.

## Точки расширения

Для нового провайдера добавьте воспроизводимые input fixtures, выберите или
расширьте profile, запустите analyzers, проверьте manifest и пересоздайте
example. Для нового semantic rule сначала добавьте evidence и safety tests,
затем меняйте generator. Independent benchmark comparator должен оставаться
независимым от деталей реализации analyzers.

Подробные safety invariants и история исследования находятся в
[`research/ARCHITECTURE_INVARIANTS.md`](../research/ARCHITECTURE_INVARIANTS.md)
и [`research/README.md`](../research/README.md).
