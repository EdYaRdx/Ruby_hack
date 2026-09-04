# Процесс разработки

## Локальная настройка

Используйте Ruby 3.3+ и установите development dependencies согласно lockfile:

```powershell
bundle install
bundle exec rspec
```

## Процесс изменения

1. Меняйте минимально необходимый loader, analyzer, profile или generator.
2. Добавляйте точечный RSpec regression для поведения и его safety boundary.
3. Запускайте полный suite и проверки Ruby syntax.
4. Пересоздавайте canonical example командой `ruby bin/update_examples`.
5. Обновляйте benchmark-backed documentation командой `ruby bin/update_docs`.
6. Проверяйте generated diff. Generated examples нельзя редактировать вручную.

Полезные команды:

```powershell
bundle exec rspec
ruby -c lib/provider_compiler.rb
ruby bin/provider_compiler inspect
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
- Не добавляйте live network calls, credentials, fake screenshots или Web UI в
  этот vertical slice.

Перед semantic change прочитайте [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) и
соответствующий research invariant. Перед изменением документации прочитайте
[`docs/DOCS_POLICY.md`](DOCS_POLICY.md).
