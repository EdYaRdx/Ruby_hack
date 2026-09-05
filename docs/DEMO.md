# Демонстрационный checkpoint: NovaPay, fail-closed и Aurora

Сценарий рассчитан на live-показ из корня репозитория. Он использует локальные
fixtures, не требует credentials и не выполняет сетевые вызовы к провайдеру.

## Подготовка

```powershell
bundle install
bundle exec rspec
bundle exec ruby bin/provider_compiler_web
```

Откройте `http://127.0.0.1:4567`. Если нужен только CLI, перейдите к разделу
[Запасной сценарий CLI](#d-запасной-сценарий-cli).

## A. Успешный сценарий NovaPay — 2–3 минуты

### Шаг 1 — загрузка

**ЧТО НАЖАТЬ:** нажмите «Загрузить пример NovaPay».

**ЧТО СКАЗАТЬ:** «Мы загружаем локальную OpenAPI-спецификацию. Workbench не
запрашивает provider и использует тот же pipeline, что и CLI».

**ОЖИДАЕМЫЙ РЕЗУЛЬТАТ:** откроется экран загрузки и анализа; будет виден статус
успешного чтения спецификации и переход к анализу.

### Шаг 2 — анализ

**ЧТО НАЖАТЬ:** откройте карточки операций и evidence.

**ЧТО СКАЗАТЬ:** «Компилятор извлекает методы, paths, параметры, auth, статусы,
ошибки и webhook-сигналы, а затем показывает происхождение каждого решения».

**ОЖИДАЕМЫЙ РЕЗУЛЬТАТ:** видны `POST /payouts` для `create_request`, `GET
/payouts/{payout_id}` для `fetch_status` с operationId `getPayoutStatus`, а
`/balance` сохранён как `EXTRA_OPERATION`.

### Шаг 3 — проверка решения

**ЧТО НАЖАТЬ:** перейдите в Review и раскройте элементы money/auth/status/webhook.

**ЧТО СКАЗАТЬ:** «Важна граница между фактом спецификации, case default,
inference и политикой адаптера».

**ОЖИДАЕМЫЙ РЕЗУЛЬТАТ:** evidence показывает, что host `operation.amount` — major
RUB, provider amount — minor/kopecks, а request conversion использует factor
`100`. `Idempotency-Key` отмечен как optional в OpenAPI; выбранная отправка
ключа — это adapter policy. Webhook показывает HMAC-SHA256,
`X-NovaPay-Signature`, raw body и hex.

### Шаг 4 — preview

**ЧТО НАЖАТЬ:** нажмите Preview и выполните create fixture, затем покажите
status fixture и completed webhook.

**ЧТО СКАЗАТЬ:** «Preview выполняет локальный generated runtime, поэтому можно
увидеть преобразование без обращения к реальному API».

**ОЖИДАЕМЫЙ РЕЗУЛЬТАТ:** `1500.50 RUB` превращается в provider amount `150050`,
а terminal provider status `completed` превращается в canonical action `approved`.

### Шаг 5 — генерация

**ЧТО НАЖАТЬ:** нажмите Generate, затем откройте список artifacts и результат
Verification.

**ЧТО СКАЗАТЬ:** «Blueprint уже разрешён; generator только проецирует его и не
пытается заново угадывать семантику».

**ОЖИДАЕМЫЙ РЕЗУЛЬТАТ:** создаются `provider_blueprint.json`,
`review_manifest.json`, `service.rb`, `fixtures.json`, `INTEGRATION.md`,
`contract_smoke.rb` и копия `provider_api.yaml`; generation и verification
завершаются успешно.

## B. Неоднозначность с безопасной остановкой — 1–2 минуты

**ЧТО НАЖАТЬ:** перезапустите загрузку и нажмите «Загрузить пример Ambiguous».
Откройте Review.

**ЧТО СКАЗАТЬ:** «Если критическая семантика не разрешена, система не маскирует
догадку под готовое сопоставление».

**ОЖИДАЕМЫЙ РЕЗУЛЬТАТ:** решение — `REVIEW_REQUIRED`, критическая проблема
помечена `BLOCKING`, evidence и unresolved item сохранены, а Generate недоступен
или возвращает отказ. В resolved Blueprint нет скрытого money factor или другого
неподтверждённого критического значения.

## C. Проверка Aurora — 30–60 секунд

**ЧТО НАЖАТЬ:** загрузите «Aurora» и покажите Analysis/Review, затем Preview.

**ЧТО СКАЗАТЬ:** «Это независимая синтетическая форма API. Здесь нет NovaPay
hardcode: проверяются другие paths, nested money и другая auth/webhook
терминология».

**ОЖИДАЕМЫЙ РЕЗУЛЬТАТ:** видны Bearer auth, `POST /transfers`, `GET
/transfers/{transfer_id}`, nested `money.value`/`money.currency`, destination,
`POST /notifications`, `X-Aurora-Signature`, HMAC-SHA256, raw body и hex.
Провайдерские `queued`, `settled`, `declined`, `voided` отображаются как
`in_progress`, `approved`, `rejected`, `rejected`; extra operations сохранены.

## D. Запасной сценарий CLI

Если браузер недоступен, из второго терминала выполните:

```powershell
ruby bin/provider_compiler inspect
ruby bin/provider_compiler generate --out tmp/demo-generated
ruby bin/provider_compiler verify --out tmp/demo-generated
```

`inspect` показывает сводку Review Manifest, `generate` создаёт ту же
проверяемую проекцию, а `verify` проверяет синтаксис Ruby и contract-smoke
harness. Для другого входа укажите явно `--spec`, `--profile` и `--defaults`.
Карточка NovaPay — явный reference-case и использует свой case profile. Обычный
загруженный OpenAPI-документ анализируется с пустыми provider defaults. Чтобы
показать общий путь, используйте fixtures Aurora или HeliosPay: их resolved
демо запускаются отдельными явными действиями.
