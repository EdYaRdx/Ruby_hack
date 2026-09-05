# Текущая архитектура

Документ описывает реализованную архитектуру. Он намеренно стабилен и не
содержит сводных значений benchmark.

## Граница системы

Компилятор принимает локальный OpenAPI-документ, профиль контракта хоста и
case defaults. Provider Blueprint создаётся только после анализа с учётом
доказательств. Ruby generator — детерминированная проекция этого Blueprint, а не
независимый источник семантики интеграции.

## Слои и ответственность

- **Вход:** OpenAPI, локальные `$ref`, `BaseServiceProfile` и case defaults.
- **Ядро:** загрузка, разрешение ссылок, неизменяемый Facts IR и fingerprint.
- **Анализ:** `OperationFact`, анализаторы, evidence, provenance и precedence.
- **Решение:** `ACCEPT`, `REVIEW_REQUIRED` или `UNKNOWN`; критические нерешённые
  вопросы получают blocking severity.
- **Blueprint:** resolved Provider Blueprint и Review Manifest — соответственно
  ЧТО и ПОЧЕМУ выбранных решений.
- **Генерация:** детерминированная Ruby-проекция без нового семантического вывода.
- **Проверка:** синтаксис Ruby, contract smoke и проверки согласованности.
- **Приложение:** orchestration общего pipeline для CLI и Web UI.
- **CLI/Web:** разные адаптеры представления над теми же слоями Application/Core.

## Web UI Demo Workbench

`lib/provider_compiler/web.rb` — тонкий WEBrick HTTP-слой, а
`lib/provider_compiler/web_renderer.rb` и `web/public/` отвечают только за
рендеринг представления и взаимодействие с браузером. Он создаёт
изолированное временное рабочее пространство на каждую загрузку, вызывает
существующий `Pipeline`, показывает `ReviewManifest`, а Preview и Generate
используют существующие сгенерированные runtime и verification. Web-слой не
добавляет новую семантическую модель, БД, аутентификацию или live provider calls.

## Конвейер

```text
исходные файлы
  -> OpenAPILoader / OpenAPIValidator
  -> FactsBuilder (неизменяемые факты провайдера)
  -> AnalyzerEngine (evidence, precedence, решения по безопасности)
  -> Evidence + ReviewManifest
  -> Resolved Provider Blueprint
  -> BlueprintValidator
  -> DeterministicGenerator
  -> Verification (синтаксис Ruby + contract smoke)
```

Локальные ссылки разрешаются до анализа. Source fingerprint включает корневой
документ, разрешённые локальные файлы и политику resolver, поэтому изменение
набора входных данных не может выглядеть как тот же самый источник провайдера.

## Семантические уровни

Facts фиксируют то, что сказано во входных данных. Evidence показывает, откуда
взято заключение. Анализаторы интерпретируют факты в рамках выбранного
`BaseServiceProfile` и case defaults. Blueprint содержит выбранное сопоставление
и его состояние решения; Review Manifest сохраняет перечень решений для проверки.

Эти обязанности разделены между следующими частями реализации:

- `lib/provider_compiler/core.rb` — загрузка, ссылки, факты и общие утилиты;
- `lib/provider_compiler/analysis.rb` — анализаторы и правила precedence/safety;
- `lib/provider_compiler/profile.rb` — контракт хоста и политика profile;
- `lib/provider_compiler/blueprint.rb` — каноническое представление и validation;
- `lib/provider_compiler/generation.rb` — детерминированный результат и verification;
- `lib/provider_compiler/application.rb` — orchestration CLI.

## Состояния безопасности

| Decision | Значение | Политика вывода |
|---|---|---|
| `ACCEPT` | Обязательная семантика разрешена с достаточными доказательствами | Blueprint можно генерировать и проверять |
| `REVIEW_REQUIRED` | Существенная неоднозначность остаётся | Сохранить evidence; при blocking-проблеме остановить генерацию |
| `UNKNOWN` | Поведение провайдера не поддержано или не восстановимо | Сохранить и сообщить item; не придумывать сопоставление |

Дополнительные endpoint-ы сохраняются как записи `EXTRA_OPERATION`. Они не
становятся каноническими методами хоста, если profile явно их не связывает.

## Контракт хоста и семантика провайдера

Profiles задают имена канонических операций хоста, словарь статусов, callback
capabilities и предположения о представлении данных. Сопоставления провайдера
остаются в Blueprint. Например, amount хоста в major units может требовать
конвертацию в provider minor units; такая конвертация является самостоятельным
значением Blueprint и проверяется до генерации.

Решения адаптера, например отправлять доступный idempotency header по выбранной
политике, представляются как `ADAPTER_POLICY`. Их нельзя выдавать за provider
specification facts: в NovaPay OpenAPI `Idempotency-Key` имеет `required: false`.

## Точки расширения

Для нового провайдера добавьте воспроизводимые входные fixtures, выберите или
расширьте profile, запустите анализаторы, проверьте manifest и пересоздайте
example. Для нового семантического правила сначала добавьте evidence и
safety-тесты, затем меняйте generator. Независимый benchmark comparator должен
оставаться независимым от деталей реализации анализаторов.

Подробные safety-инварианты и история исследования находятся в
[`research/ARCHITECTURE_INVARIANTS.md`](../research/ARCHITECTURE_INVARIANTS.md)
и [`research/README.md`](../research/README.md).

## Контракт входов GOAL 5

OpenAPI — основной источник фактов провайдера и документированной семантики.
`CaseDefaults` — необязательные явные переопределения или резервные знания
провайдера; их нельзя выводить из имени файла, fingerprint или общего кода
анализаторов. Явный `--spec` без `--defaults` использует
`fixtures/empty_case_defaults.yml`. Поэтому spec-only анализ показывает реальные
решения REVIEW/UNKNOWN, а не молча импортирует семантику NovaPay.

Существующий pipeline Facts IR -> Review Manifest -> Provider Blueprint не
изменён. Успешные HTTP-коды переносятся из OpenAPI в Blueprint и generator;
категории runtime-ошибок, обработка Retry-After и provenance fixtures являются
проекциями resolved Blueprint.
