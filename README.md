# Компилятор интеграций с провайдерами

Компилятор интеграций с контролем доказательности для платёжных провайдеров.

Он преобразует OpenAPI-документ провайдера в проверенную Provider Blueprint и
детерминированную проекцию Ruby-адаптера:

```text
OpenAPI + local refs
  -> resolved immutable Facts IR
  -> analyzers and evidence
  -> Review Manifest
  -> Provider Blueprint
  -> Ruby adapter, fixtures, integration notes
  -> syntax and contract verification
```

## Проблема

OpenAPI описывает структуру транспорта. Платёжной интеграции требуется также
смысл, зависящий от провайдера: какой endpoint создаёт выплату, передаются ли
деньги в основных единицах или в копейках, как статусы связываются с действиями
хост-системы, как проверяются webhook и безопасны ли повторы запросов. Эти
семантические решения нельзя надёжно получить обычным генератором клиентов из
схемы.

Проект делает такие решения явными, связывает их с доказательствами и блокирует
небезопасную генерацию, когда критический факт не разрешён.

## Чем проект отличается от обычной генерации OpenAPI

Компилятор — это не просто генератор клиентских заглушек. Это семантический
контур безопасности вокруг небольшой детерминированной проекции. Он различает:

- `SPEC_FACT` — непосредственно подтверждённый документом провайдера факт;
- `CASE_DEFAULT` — значение из fixture конкретного интеграционного кейса;
- `INFERENCE` — оценочную интерпретацию сигналов провайдера;
- `ADAPTER_POLICY` — решение реализации, например отправлять доступный
  idempotency key при каждом подходящем запросе.

`ACCEPT` разрешает генерацию. `REVIEW_REQUIRED` сохраняет доказательства и
блокирует или ограничивает генерацию при нерешённой blocking-проблеме.
`UNKNOWN` сохраняет и сообщает неподдержанную информацию, не подменяя её
выдуманным mapping.

## Текущее состояние реализации

Снимок возможностей ниже генерируется из checkout проекта, canonical example и
результатов проверок. Он обновляется командой `bin/update_docs`.

<!-- BEGIN GENERATED: CAPABILITIES -->
- Загрузка и проверка OpenAPI, локальные references и source fingerprinting: присутствует `lib/provider_compiler/core.rb`.
- Анализ с учётом evidence, Review Manifest и Provider Blueprint: реализации analyzer/profile/blueprint присутствуют.
- Детерминированная Ruby-проекция и verification: реализация generator присутствует.
- Канонический пример NovaPay: 7 файлов в `examples/novapay/` (`INTEGRATION.md`, `contract_smoke.rb`, `fixtures.json`, `provider_api.yaml`, `provider_blueprint.json`, `review_manifest.json`, `service.rb`).
- Independent semantic validation: benchmark NovaPay и сравнение Aurora входят в сгенерированный статус выше.
- Live provider calls и Web UI: в этом vertical slice не реализованы; Web UI остаётся планом.

Для обновления снимка запустите `ruby bin/update_docs`.
<!-- END GENERATED: CAPABILITIES -->

## Быстрый старт

Требуется Ruby 3.3+ (рекомендуется); gemspec требует Ruby >= 3.0.

```powershell
bundle install
bundle exec rspec
ruby -c lib/provider_compiler.rb
ruby bin/provider_compiler inspect
ruby bin/provider_compiler generate --out tmp/generated
ruby bin/provider_compiler verify --out tmp/generated
```

Другой документ провайдера можно передать через `--spec PATH` или указать в
`PROVIDER_SPEC`. Профили и case defaults являются явными входами, поэтому
провайдерская специфика не находится внутри generic analyzer-кода.

## Эталонный пример NovaPay

Воспроизводимый источник —
[`fixtures/novapay_provider_api.yaml`](fixtures/novapay_provider_api.yaml).
Каноническая сгенерированная проекция поддерживается командой
`bin/update_examples` в каталоге [`examples/novapay/`](examples/novapay/).

Эталонный кейс показывает:

- `POST /payouts` -> `create_request`;
- `GET /payouts/{payout_id}` -> `fetch_status`, operationId
  `getPayoutStatus`;
- `operation.amount` хоста как major RUB и amount провайдера как minor kopecks;
  request conversion — `major -> minor` с factor `100`;
- необязательный по OpenAPI `Idempotency-Key`; поведение always-send
  представлено как политика адаптера;
- `/balance` сохраняется как неблокирующий `EXTRA_OPERATION`;
- проверку подписи webhook и действия для terminal status.

Сгенерированные файлы включают Blueprint, Review Manifest, Ruby-сервис,
runtime fixtures, integration notes и contract-smoke harness. Это generated
artifacts: изменяйте fixture/profile/defaults и запускайте updater, а не
редактируйте результат вручную.

## Статус проверки

Следующий блок генерируется `bin/update_docs` на основе реальных benchmark
runner-ов и текущего запуска RSpec. Числа не копируются вручную.

<!-- BEGIN GENERATED: PROJECT_STATUS -->
**Текущая проверка (сгенерировано автоматически)**

- RSpec: 42 examples, failures: 0.
- Mutation cases NovaPay: безопасно пройдено 37/37; decision accuracy: 100.0%; safe decision coverage: 100.0%.
- ACCEPT rate: 48.6%; REVIEW_REQUIRED rate: 40.5%; UNKNOWN rate: 10.8%.
- Independent semantic ACCEPT accuracy: 100.0%; critical false ACCEPTs: 0.
- Aurora: levels 3/3, behavioral vectors 4/4; semantic accuracy: 100.0%.

Для обновления блока запустите `ruby bin/update_docs`.
<!-- END GENERATED: PROJECT_STATUS -->

## Навигация по репозиторию

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — текущая архитектура и
  инварианты;
- [`docs/BENCHMARK.md`](docs/BENCHMARK.md) — методика, формулы и актуальные
  результаты;
- [`docs/DEMO.md`](docs/DEMO.md) — воспроизводимый CLI-сценарий;
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — процесс разработки и проверок;
- [`docs/DOCS_POLICY.md`](docs/DOCS_POLICY.md) — правила для стабильной и
  generated-документации;
- [`docs/GLOSSARY.md`](docs/GLOSSARY.md) — единый словарь терминов;
- [`THIRD_PARTY.md`](THIRD_PARTY.md) — зависимости и лицензии;
- [`research/README.md`](research/README.md) — supporting research и audit
  artifacts.

## Структура проекта

```text
bin/                    CLI и deterministic updaters документации/examples
lib/provider_compiler/  loader, facts, analyzers, blueprint и generator
profiles/               host-contract profiles
fixtures/               reproducible provider specs, defaults и Aurora truth
examples/               generated, reviewable provider projections
spec/                   RSpec regression и semantic validation suite
research/               benchmark corpus, independent comparator и history
docs/                   стабильная engineering и judge-facing documentation
```

## Область применения и ограничения

Это production-oriented vertical slice, а не заявление о поддержке любого
провайдера. Для нового провайдера всё равно нужны явные profile, case defaults
и review полученного manifest. Текущий CLI работает с локальными входами;
загрузка по сети, реальные credentials, deployment и Web UI находятся вне
области этого этапа.

Для расширения системы используйте [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)
и соблюдайте инварианты безопасности из
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
