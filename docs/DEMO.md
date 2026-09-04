# Demo checkpoint: NovaPay, fail-closed и Aurora

Сценарий рассчитан на live-показ из корня репозитория. Он использует локальные
fixtures, не требует credentials и не выполняет сетевые вызовы к провайдеру.

## Подготовка

```powershell
bundle install
bundle exec rspec
bundle exec ruby bin/provider_compiler_web
```

Откройте `http://127.0.0.1:4567`. Если нужен только CLI, перейдите к разделу
[CLI fallback](#d-cli-fallback).

## A. NovaPay happy path — 2–3 минуты

### Шаг 1 — Upload

**WHAT TO CLICK:** нажмите «Загрузить пример NovaPay».

**WHAT TO SAY:** «Мы загружаем локальную OpenAPI-спецификацию. Workbench не
запрашивает provider и использует тот же pipeline, что и CLI».

**EXPECTED RESULT:** откроется экран Upload/Analysis; будет виден статус
успешного чтения спецификации и переход к анализу.

### Шаг 2 — Analysis

**WHAT TO CLICK:** откройте карточки операций и evidence.

**WHAT TO SAY:** «Компилятор извлекает методы, paths, параметры, auth, статусы,
ошибки и webhook-сигналы, а затем показывает происхождение каждого решения».

**EXPECTED RESULT:** видны `POST /payouts` для `create_request`, `GET
/payouts/{payout_id}` для `fetch_status` с operationId `getPayoutStatus`, а
`/balance` сохранён как `EXTRA_OPERATION`.

### Шаг 3 — Review

**WHAT TO CLICK:** перейдите в Review и раскройте money/auth/status/webhook
items.

**WHAT TO SAY:** «Важна граница между фактом спецификации, case default,
inference и политикой адаптера».

**EXPECTED RESULT:** evidence показывает, что host `operation.amount` — major
RUB, provider amount — minor/kopecks, а request conversion использует factor
`100`. `Idempotency-Key` отмечен как optional в OpenAPI; выбранная отправка
ключа — это adapter policy. Webhook показывает HMAC-SHA256,
`X-NovaPay-Signature`,
raw body и hex.

### Шаг 4 — Preview

**WHAT TO CLICK:** нажмите Preview и выполните create fixture, затем покажите
status fixture и completed webhook.

**WHAT TO SAY:** «Preview выполняет локальный generated runtime, поэтому можно
увидеть преобразование без обращения к реальному API».

**EXPECTED RESULT:** `1500.50 RUB` превращается в provider amount `150050`, а
terminal provider status `completed` превращается в canonical action `approved`.

### Шаг 5 — Generate

**WHAT TO CLICK:** нажмите Generate, затем откройте список artifacts и результат
Verification.

**WHAT TO SAY:** «Blueprint уже разрешён; generator только проецирует его и не
пытается заново угадывать семантику».

**EXPECTED RESULT:** создаются `provider_blueprint.json`,
`review_manifest.json`, `service.rb`, `fixtures.json`, `INTEGRATION.md`,
`contract_smoke.rb` и копия `provider_api.yaml`; generation и verification
завершаются успешно.

## B. Fail-closed ambiguity — 1–2 минуты

**WHAT TO CLICK:** перезапустите Upload и нажмите «Загрузить пример Ambiguous».
Откройте Review.

**WHAT TO SAY:** «Если критическая семантика не разрешена, система не маскирует
догадку под готовый mapping».

**EXPECTED RESULT:** решение — `REVIEW_REQUIRED`, критическая проблема помечена
`BLOCKING`, evidence и unresolved item сохранены, а Generate недоступен или
возвращает отказ. В resolved Blueprint нет скрытого money factor или другого
неподтверждённого критического значения.

## C. Aurora universality check — 30–60 секунд

**WHAT TO CLICK:** загрузите «Aurora» и покажите Analysis/Review, затем Preview.

**WHAT TO SAY:** «Это независимая синтетическая форма API. Здесь нет NovaPay
hardcode: проверяются другие paths, nested money и другая auth/webhook
терминология».

**EXPECTED RESULT:** видны Bearer auth, `POST /transfers`, `GET
/transfers/{transfer_id}`, nested `money.value`/`money.currency`, destination,
`POST /notifications`, `X-Aurora-Signature`, HMAC-SHA256, raw body и hex.
Провайдерские `queued`, `settled`, `declined`, `voided` отображаются как
`in_progress`, `approved`, `rejected`, `rejected`; extra operations сохранены.

## D. CLI fallback

Если браузер недоступен, из второго терминала выполните:

```powershell
ruby bin/provider_compiler inspect
ruby bin/provider_compiler generate --out tmp/demo-generated
ruby bin/provider_compiler verify --out tmp/demo-generated
```

`inspect` показывает summary Review Manifest, `generate` создаёт ту же
проверяемую проекцию, а `verify` проверяет Ruby syntax и contract-smoke harness.
Для другого входа укажите явно `--spec`, `--profile` и `--defaults`.
