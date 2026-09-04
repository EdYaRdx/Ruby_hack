# Глоссарий

| Термин | Значение в проекте |
|---|---|
| Provider Compiler | Компилятор, который переводит provider OpenAPI в проверяемую host-интеграцию, а не просто в API client. |
| Provider Integration Workbench | Локальная Web UI-оболочка для Upload, Analysis, Review, Preview и Generate. |
| Facts IR | Неизменяемое внутреннее представление фактов, извлечённых из OpenAPI; оно не содержит придуманных semantic decisions. |
| OperationFact | Нормализованный факт об operation: method, path, operationId, параметры и доступные сигналы. |
| BaseServiceProfile | Явный профиль canonical host-контракта: операции, статусы, поля, auth и capabilities. |
| Analyzer | Компонент, который сопоставляет facts с profile/case defaults и выпускает candidate decisions с evidence. |
| Evidence | Доказательства и source locations, на которых основано решение analyzer. |
| Provenance | Тип и ссылка на происхождение значения: `SPEC_FACT`, `CASE_DEFAULT`, `INFERENCE` или `ADAPTER_POLICY`. |
| Decision | Безопасностное состояние результата: `ACCEPT`, `REVIEW_REQUIRED` или `UNKNOWN`. |
| Provider Blueprint | Проверенная canonical model интеграции, из которой строятся generated projections. |
| Resolved Blueprint | Blueprint после разрешения допустимых overrides и проверок; это источник для generation. |
| Review Manifest | Перечень proposed mappings, decisions, conflicts и unresolved items для review. |
| Override | Явная локальная правка входного решения с provenance, scope и проверкой свежести fingerprint. |
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
| Deterministic Generation | Повторяемая генерация одинаковых artifacts из одного resolved Blueprint без скрытой эвристики. |
| Verification | Проверка сгенерированных Ruby-файлов, contract smoke и согласованности output. |
| Contract Smoke | Малый runtime harness, проверяющий generated request/response/callback contract на fixture-данных. |
| Mutation Benchmark | Hand-authored adversarial corpus, который сравнивает decision, семантику и safety с ground truth. |

Названия классов, методов, файлов, CLI-команд, JSON/YAML-ключей и machine-readable
metrics сохраняются в оригинальном виде, чтобы документация не расходилась с
кодом и tooling.
