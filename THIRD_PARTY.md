# Сторонние зависимости

Проект намеренно небольшой и локальный. Он не требует внешнего runtime-сервиса
или удалённого API провайдера: текущий runtime детерминированный, а нейросетевой
runtime не используется.

Авторитетные объявления зависимостей находятся в [`Gemfile`](Gemfile),
[`Gemfile.lock`](Gemfile.lock) и [`provider_compiler.gemspec`](provider_compiler.gemspec).
Ниже указаны версии из lockfile; лицензии сверены по установленным gem
specifications, использованным при проверке текущего checkout.

| Пакет | Версия | Назначение | Лицензия в metadata |
|---|---:|---|---|
| `bigdecimal` | 3.1.5 | точные money conversions во время выполнения | Ruby; BSD-2-Clause |
| `rspec` | 3.13.2 | development/test runner | MIT |
| `rspec-core` | 3.13.6 | реализация test runner | MIT |
| `rspec-expectations` | 3.13.5 | assertions | MIT |
| `rspec-mocks` | 3.13.8 | test doubles | MIT |
| `rspec-support` | 3.13.7 | библиотека поддержки RSpec | MIT |
| `diff-lcs` | 1.6.2 | comparison support для RSpec | MIT; Artistic-1.0-Perl; GPL-2.0-or-later |
| `bundler` | 2.5.22 | build/dependency tool из lockfile | MIT |
| `webrick` | 1.9.2 | локальный Web UI HTTP-сервер | Ruby; BSD-2-Clause |

Ruby и его standard library являются prerequisites, поставляемыми runtime; этот
репозиторий их не vendored. Для запуска tests, generation и benchmark не нужны
credentials или сетевой доступ к провайдеру.

Web UI использует `webrick` 1.9.2 из RubyGems как небольшой локальный
HTTP-сервер. Он не добавляет внешние runtime API или сетевые вызовы к provider.
