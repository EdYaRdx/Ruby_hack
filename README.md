# Provider Compiler

Принимает OpenAPI платёжного провайдера, строит проверенный Provider Blueprint
для Space Payments и детерминированно генерирует Ruby adapter, docs и fixtures.

Он преобразует OpenAPI-документ провайдера в проверенную Provider Blueprint и
детерминированную проекцию Ruby-адаптера:

```text
OpenAPI + local refs
  -> immutable Facts IR
  -> Analyzers
  -> Evidence + Review Manifest
  -> Resolved Provider Blueprint
  -> Validation
  -> Deterministic Generation
  -> Verification
```

## Проблема

OpenAPI описывает структуру транспорта. Платёжной интеграции требуется также
смысл, зависящий от провайдера: какой endpoint создаёт выплату, передаются ли
деньги в основных единицах или в копейках, как статусы связываются с действиями
хост-системы, как проверяются webhook и безопасны ли повторы запросов. Эти
семантические решения нельзя надёжно получить обычным генератором клиентов из
схемы.

На практике ручная интеграция нового платёжного провайдера занимает примерно
2–5 дней: нужно отдельно разобрать transport contract, money units, statuses,
webhooks, retries и host adapter.

Проект делает такие решения явными, связывает их с доказательствами и блокирует
небезопасную генерацию, когда критический факт не разрешён.

## Чем проект отличается от обычной генерации OpenAPI

Компилятор — это не просто генератор клиентских заглушек. Это семантический
контур безопасности вокруг небольшой детерминированной проекции. Он различает:

Обычный OpenAPI Generator строит `OpenAPI → API client`. Здесь поток другой:
`OpenAPI → payment semantics → Provider Blueprint → BaseService adapter`, с
отдельной проверкой доказательств и safety decision.

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
- Независимая semantic validation: benchmark NovaPay и сравнение Aurora входят в сгенерированный статус выше.
- Live provider calls не реализованы; Web UI Demo Workbench реализован в `lib/provider_compiler/web.rb`, `lib/provider_compiler/web_renderer.rb` и `web/public/`.

Для обновления снимка запустите `ruby bin/update_docs`.
<!-- END GENERATED: CAPABILITIES -->

## Быстрый старт

Требуется Ruby >= 3.0; текущий checkout проверен на Ruby 4.0.6 и Bundler 2.5.22.

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
- sandbox base URL из официальной спецификации: `https://api.sandbox.novapay.example/v1`;
- `operation.amount` хоста как major RUB и amount провайдера как minor kopecks;
  request conversion — `major -> minor` с factor `100`;
- необязательный по OpenAPI `Idempotency-Key`; по умолчанию адаптер отправляет
  переданный ключ (`if_available`), а `--always-send-idempotency` — явная политика
  адаптера, не факт спецификации;
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

- RSpec: 59 examples, failures: 0.
- Mutation benchmark NovaPay: безопасно пройдено 37/37; decision_accuracy: 100.0%; safe_decision_coverage: 100.0%.
- automatic_accept_rate: 48.6%; review_required_rate: 40.5%; unknown_rate: 10.8%.
- semantic_accept_accuracy: 100.0%; critical_false_accept_count: 0.
- Aurora: levels 3/3, behavioral vectors 4/4; semantic_accuracy: 100.0%.

Для обновления блока запустите `ruby bin/update_docs`.
<!-- END GENERATED: PROJECT_STATUS -->

## Web UI Demo Workbench

Локальный Workbench показывает тот же конвейер, не меняя семантику компилятора:

```powershell
bundle exec ruby bin/provider_compiler_web
```

Откройте `http://127.0.0.1:4567`, нажмите «Загрузить пример NovaPay» и пройдите
экраны «Загрузка» → «Анализ» → «Review» → «Preview» → «Generate». В Analysis
видны методы, операции, evidence и денежная семантика; Preview показывает
runtime fixture, а Generate создаёт те же детерминированные артефакты и запускает
Verification. Кнопки Ambiguous и Aurora демонстрируют fail-closed и переносимость
на другую форму API. Реальных сетевых вызовов к провайдеру нет.

Регрессионное покрытие UI находится в [`spec/web_spec.rb`](spec/web_spec.rb).

## Навигация по репозиторию

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — текущая архитектура и
  инварианты;
- [`docs/BENCHMARK.md`](docs/BENCHMARK.md) — методика, формулы и актуальные
  результаты;
- [`docs/DEMO.md`](docs/DEMO.md) — готовый live-сценарий для Web UI, fail-closed,
  Aurora и CLI fallback;
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — процесс разработки и проверок;
- [`docs/DOCS_POLICY.md`](docs/DOCS_POLICY.md) — правила для стабильной и
  generated-документации;
- [`docs/GLOSSARY.md`](docs/GLOSSARY.md) — единый словарь терминов;
- [`THIRD_PARTY.md`](THIRD_PARTY.md) — зависимости и лицензии;
- [`research/README.md`](research/README.md) — supporting research и audit
  artifacts с явным разделением текущих и исторических материалов.

## Структура проекта

```text
bin/                    CLI, Web entrypoint и детерминированные updater-ы
lib/provider_compiler/  Facts IR, analyzers, Blueprint, generation, Web/API
profiles/               BaseServiceProfile для host-контракта
fixtures/               OpenAPI, case defaults и независимая Aurora ground truth
examples/               сгенерированные и проверяемые provider projections
spec/                   RSpec regression, semantic и Web UI проверки
research/               benchmark corpus, comparator и исторические материалы
docs/                   актуальная engineering и judge-facing документация
```

## Область применения и ограничения

Это исследовательский hackathon prototype, а не production-ready SaaS и не
заявление о поддержке любого провайдера. Для нового провайдера всё равно нужны
явные profile, case defaults и review полученного manifest. BaseService в текущем
репозитории представлен тестовым host-контрактом/сгенерированным harness; live
вызовы провайдера, production credentials и deployment не входят в scope.

## Безопасность и соответствие ограничениям

Спецификации обрабатываются локально; UI не сохраняет production credentials и
не выполняет вызовы провайдера. Текущая политика разрешает локальные `$ref`, а
неподдержанные remote refs отклоняются. В runtime нет нейросетевой модели и нет
обязательной проприетарной зависимости; проект использует Ruby и open-source
gems. Ruby — основной язык реализации и составляет более 50% исходного кода.
Неизвестная или критически неоднозначная семантика сохраняется в Review Manifest
и не превращается молча в ACCEPT.

Для расширения системы используйте [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)
и соблюдайте инварианты безопасности из
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
