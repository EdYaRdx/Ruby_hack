# Политика документации

Репозиторий разделяет долговечные объяснения и факты, которые генерируются
текущей реализацией.

| Артефакт | Назначение | Source of truth | Способ обновления |
|---|---|---|---|
| `README.md` | точка входа для пользователя и judge | стабильное описание, artifacts репозитория и benchmark JSON | prose редактируется вручную; updater владеет отмеченными capability/status blocks |
| `docs/ARCHITECTURE.md` | текущая архитектура и invariants | `lib/`, profiles и проверенные design rules | вручную, с review |
| `docs/BENCHMARK.md` | методика и текущие metrics | benchmark JSON и RSpec JSON от runners | методика вручную; updater владеет отмеченным metrics block |
| `docs/DEMO.md` | воспроизводимый walkthrough | реальные CLI-команды и generator output | вручную; без выдуманного output |
| `docs/DEVELOPMENT.md` | workflow для разработчика | scripts и tests репозитория | вручную, с review |
| `docs/GLOSSARY.md` | единый словарь терминов | согласованная терминология проекта | вручную, при появлении новых terms |
| `examples/novapay/` | canonical generated projection | NovaPay fixture, profile, defaults и generator | `ruby bin/update_examples`; вручную не редактировать |
| `THIRD_PARTY.md` | зависимости и license manifest | `Gemfile`, `Gemfile.lock`, gemspec и gem metadata | обновлять при изменении dependencies |
| `research/` | supporting evidence и historical research | benchmark corpus и research decisions | snapshots могут быть историческими; актуальные результаты — в `docs/` |

## Updater-ы

`bin/update_examples` пересоздаёт только `examples/novapay/`, копирует
committed fixture как `provider_api.yaml`, запускает настоящий generator и
завершается ошибкой, если verification не прошла.

`bin/update_docs` запускает настоящий mutation benchmark, Aurora benchmark и
RSpec suite, затем заменяет только точные generated blocks в README и
`docs/BENCHMARK.md`. Для одинаковых входов он детерминирован и не добавляет
timestamps в committed documentation.

Если source result отсутствует или marker повреждён, updater обязан завершиться
ошибкой, а не сохранять устаревшие числа и не придумывать замену.
