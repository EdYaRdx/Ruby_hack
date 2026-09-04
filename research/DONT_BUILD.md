# Что не следует строить в hackathon MVP

> **POLICY RECORD.** Упомянутые ниже LLM, embeddings, neural models и внешние
> neural APIs — явно исключённые исторические альтернативы. Текущий prototype
> работает на детерминированном Ruby pipeline и не использует их.

Эти элементы намеренно исключены после сравнения ожидаемого прироста score с
risk solo implementation.

## Исключённые алгоритмы

- LLM, embeddings, neural models и внешние neural APIs: это запрещено правилами
  кейса и не нужно для explainability.
- TF-IDF/BM25: lexical retrieval не доказывает money units, idempotency или final
  status semantics; benchmark не показывает достаточной пользы.
- Полный fuzzy semantic mapping: он полезен только для предложения candidate на
  review; blind acceptance создаёт critical false accepts.
- Graph/lifecycle inference: интересно для multi-provider product, но требует
  слишком много graph modeling для reference case и не нужно по rubric.

## Исключённый product scope

- Web UI: детерминированный `OptionParser` CLI показывает полный flow с меньшей
  failure surface.
- Runtime network calls к реальному provider: для безопасной hackathon demo
  достаточно fixtures и generated adapter.
- Автоматическое угадывание undocumented currency units, retry rules или
  signature algorithms.
- Произвольная natural-language conditional logic; поддерживаются только
  bounded patterns.
- Полная OpenAPI code generation для каждой request/response model; unknown
  schemas сохраняются и сообщаются.
- Provider-specific DSL до стабилизации Blueprint schema.
- Generated integration tests для каждой operation до того, как green станут
  golden tests и mutation gate.

## Ловушки зависимостей

- Не зависите одновременно от `openapi_first` и другой полной OpenAPI object model.
- Не добавляйте Thor ради одной команды.
- Не добавляйте `amatch` только потому, что fuzzy matching технически интересен.
- Не заставляйте ERB templates разбирать descriptions или принимать semantic decisions.

## Правило остановки

Если элемент не улучшает измеряемый rubric criterion, не уменьшает critical
false accepts и не делает core demo более проверяемой, его следует отложить до
окончания MVP.
