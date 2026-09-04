# CLI-демонстрация

Это реальный сценарий репозитория. Он использует воспроизводимую NovaPay
fixture и не обращается к провайдеру.

Из корня репозитория:

```powershell
bundle install
bundle exec rspec
ruby bin/provider_compiler inspect
ruby bin/provider_compiler generate --out tmp/demo-generated
ruby bin/provider_compiler verify --out tmp/demo-generated
ruby bin/update_examples
ruby bin/update_docs
```

Первая команда inspection печатает summary Review Manifest. Generation создаёт:

```text
provider_blueprint.json
review_manifest.json
service.rb
fixtures.json
INTEGRATION.md
contract_smoke.rb
```

Сгенерированный NovaPay service показывает conversion host major-RUB amount в
provider minor amount, mapping статусов, optional idempotency policy и
fail-closed проверку webhook. `verify` компилирует generated Ruby и запускает
его contract-smoke harness.

Для другого провайдера передайте `--spec`, `--profile` и `--defaults` явно:

```powershell
ruby bin/provider_compiler inspect --spec path/to/provider_api.yaml --profile profiles/space_payments_v1.yml --defaults fixtures/novapay_case_defaults.yml
```

## Web UI Demo Workbench

Запустите локальный сервер:

```powershell
bundle exec ruby bin/provider_compiler_web
```

Откройте `http://127.0.0.1:4567`. Workbench поддерживает локальную загрузку OpenAPI,
демо NovaPay/Ambiguous/Aurora, Analysis с evidence, fail-closed Review, runtime Preview
и генерацию тех же артефактов через существующие `Pipeline`, `Blueprint`,
`DeterministicGenerator` и `Verification`. Сетевые вызовы к provider не выполняются.
