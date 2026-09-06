# Матрица поддержки OpenAPI

Матрица описывает фактическое поведение текущего checkout. Она не обещает
полную реализацию OpenAPI и не превращает `REVIEW_REQUIRED` в автоматическое
принятие решения.

| Возможность | Статус | Фактическое поведение |
|---|---|---|
| OpenAPI 3.x YAML/JSON | SUPPORTED | Загружается через `YAML.safe_load`/`JSON.parse`; корневой документ должен быть объектом. |
| OpenAPI 2.x и неизвестная версия | REJECTED_FOR_SAFETY | `OpenAPIValidator` выдаёт диагностическую ошибку. |
| Локальный `$ref` внутри root directory | SUPPORTED | Разрешается рекурсивно; все локальные inputs входят в fingerprint. |
| Локальный `$ref` через traversal или symlink | REJECTED_FOR_SAFETY | Проверяются canonical paths; выход за root запрещён. |
| Remote `$ref` | UNSUPPORTED | Отклоняется с явной диагностикой; сетевой fetch не выполняется. |
| Broken JSON Pointer / отсутствующий файл | UNSUPPORTED | Загрузка завершается `RefError`, без partial generation. |
| Recursive/deep/huge local ref graph | REJECTED_FOR_SAFETY | Применяются лимиты размера файла, глубины и числа узлов. |
| `allOf` / `oneOf` / `anyOf` | PARTIAL | Сохраняются в resolved Facts/constraints; полное семантическое объединение не обещается. |
| Nullable / OpenAPI 3.1-only features | UNSUPPORTED | Если feature меняет mapping, требуется review или явное diagnostic. |
| `application/json` request/response | SUPPORTED | Используется canonical request/response mapping. |
| Другой media type без JSON mapping | PARTIAL | Факт сохраняется, но генерация не угадывает body contract и может быть заблокирована. |
| Server variables | PARTIAL | Значение URL сохраняется; runtime substitution не выводится автоматически. |
| API key в header/query | SUPPORTED | Header/query стратегия сохраняется; query передаётся и через fallback transport. |
| Bearer header | SUPPORTED | Генерируется `Authorization: Bearer <key>`. |
| OAuth2, cookie auth, неизвестные schemes | UNSUPPORTED | Не выбираются silently; decision остаётся `UNKNOWN`/blocking. |
| Required custom query/header/cookie parameter | REJECTED_FOR_SAFETY | Добавляется `unsupported_features` с `generation_impact: BLOCKING`; value не теряется. |
| Optional custom parameter | PARTIAL | Сохраняется как non-blocking diagnostic; canonical adapter его автоматически не отправляет. |
| Invalid or oversized provider regex | REJECTED_FOR_SAFETY | Анализ помечает blocking issue; generator повторно проверяет pattern и не исполняет его. |
| Webhook HMAC raw body | SUPPORTED when explicit | Подпись проверяется до JSON parsing при полном evidence. |
| Webhook event/status contradiction | REJECTED_FOR_SAFETY | Runtime возвращает failure и не вызывает approve/reject action. |
| Webhook без достаточной signature semantics | REVIEW_REQUIRED | Генерация блокируется до разрешения critical ambiguity. |
| Extra endpoint | SUPPORTED as preservation | Сохраняется как non-blocking `EXTRA_OPERATION`, если profile не объявляет canonical binding. |
| Provider-controlled text in UI/docs | PARTIAL | HTML renderer экранирует text; generated Ruby class names и URLs проходят safety validation. |

## Неизменённая граница host contract

Официальное case description подтверждает концептуальные методы `BaseService`,
но не даёт production signature для constructor, HTTP client и failure/result
objects. Поэтому generated adapter использует profile-driven failure argument list
и один canonical transport shape, но production совместимость с неизвестным
host class всё ещё требует реального host contract.

