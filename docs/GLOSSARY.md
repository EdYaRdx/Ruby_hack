# Глоссарий

| Термин | Значение в проекте |
|---|---|
| Facts IR | Неизменяемое внутреннее представление фактов, извлечённых из OpenAPI; оно не содержит придуманных semantic decisions. |
| Evidence | Доказательства и source locations, на которых основано решение analyzer. |
| Provider Blueprint | Проверенная canonical model интеграции, из которой строятся generated projections. |
| Review Manifest | Перечень proposed mappings, decisions, conflicts и unresolved items для review. |
| `SPEC_FACT` | Факт, прямо подтверждённый provider specification. |
| `CASE_DEFAULT` | Значение, заданное для конкретного provider/case и не являющееся универсальным фактом. |
| `INFERENCE` | Кандидат semantic mapping, предложенный анализом по сигналам; критический inference сам по себе не является разрешением. |
| `ADAPTER_POLICY` | Решение реализации адаптера, например политика отправки idempotency key. |
| `ACCEPT` | Состояние, при котором необходимые semantics разрешены и generation допускается. |
| `REVIEW_REQUIRED` | Состояние, при котором существенная неоднозначность требует проверки; blocking issues останавливают generation. |
| `UNKNOWN` | Неподдержанная или неразрешимая информация, которую система сохраняет и сообщает без скрытого mapping. |
| `EXTRA_OPERATION` | Provider endpoint, сохранённый отдельно от canonical BaseService operations. |
| Source of truth | Источник истины для конкретного факта или документа; generated output не является самостоятельным источником. |
| Ground truth | Независимо заданный ожидаемый результат, используемый comparator-ом. |
| Fingerprint | Сводный идентификатор root input, resolved local refs и resolver policy. |
| Fail-closed | Безопасный отказ: при критической неопределённости система не генерирует небезопасное поведение. |

Названия классов, методов, файлов, CLI-команд, JSON/YAML-ключей и machine-readable
metrics сохраняются в оригинальном виде, чтобы документация не расходилась с
кодом и tooling.
