# Процесс разработки

## Предварительные условия и локальный запуск

Gemspec требует Ruby `>= 3.0`; текущий checkout проверен на Ruby 4.0.6 и
Bundler 2.5.22. Виртуальное окружение не нужно: зависимости устанавливаются
Bundler-ом в обычный Ruby environment.

```powershell
ruby --version
bundle --version
bundle install
bundle exec rspec
```

Для ручной проверки Web UI:

```powershell
bundle exec ruby bin/provider_compiler_web
```

После запуска откройте `http://127.0.0.1:4567`. Хост и порт можно изменить
переменными `PROVIDER_COMPILER_WEB_HOST` и `PROVIDER_COMPILER_WEB_PORT`.
UI-тесты находятся в `spec/web_spec.rb`; они проверяют upload, demo-сценарии,
Review safety, runtime Preview и generated artifacts.

## Процесс изменения

1. Меняйте минимально необходимый loader, analyzer, profile или generator.
2. Добавляйте точечный RSpec regression для поведения и его safety boundary.
3. Запускайте полный suite и проверки Ruby syntax.
4. Пересоздавайте canonical example командой `ruby bin/update_examples`.
5. Обновляйте benchmark-backed documentation командой `ruby bin/update_docs`.
6. Проверяйте generated diff: `examples/novapay/` нельзя редактировать вручную.

Полезные команды:

```powershell
bundle exec rspec
ruby -c lib/provider_compiler.rb
ruby bin/provider_compiler --help
ruby bin/provider_compiler inspect
ruby bin/provider_compiler analyze --spec fixtures/novapay_provider_api.yaml
ruby bin/provider_compiler generate --out tmp/generated
ruby bin/provider_compiler verify --out tmp/generated
ruby research/benchmark/run.rb
ruby research/benchmark/second_provider.rb
ruby bin/update_examples
ruby bin/update_docs
```

## Правила проектирования

- Различайте provider facts, evidence, inference и adapter policy.
- Храните canonical host mappings в profiles/Blueprints, а не в templates.
- Сохраняйте extra operations и неподдержанную информацию.
- Считайте money units, terminal statuses, webhook verification и retry
  idempotency safety-sensitive областями.
- Не превращайте `REVIEW_REQUIRED` или `UNKNOWN` в тихий `ACCEPT`.
- Generator не выводит семантику самостоятельно: он получает уже разрешённый
  Blueprint.
- Web UI остаётся presentation adapter над тем же Application/Core pipeline и не
  дублирует analyzers, mapper-ы или BlueprintValidator.
- Не добавляйте live network calls, credentials или внешние runtime services.

Перед semantic change прочитайте [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) и
соответствующие invariants. Перед изменением документации прочитайте
[`docs/DOCS_POLICY.md`](DOCS_POLICY.md).

## Windows

Команды выше работают в PowerShell из корня репозитория. Если `ruby` или
`bundle` не найдены, установите RubyInstaller с MSYS2 toolchain и откройте новый
терминал; отдельное Python virtual environment для проекта не требуется.
