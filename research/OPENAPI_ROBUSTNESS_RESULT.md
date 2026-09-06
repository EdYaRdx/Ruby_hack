# Hostile OpenAPI robustness result

OpenAPI рассматривается как недоверенный input. Цель — не поддержать весь
стандарт, а дать корректный `SUPPORTED`/`PARTIAL`/`REVIEW_REQUIRED`/
`UNSUPPORTED`/`REJECTED_FOR_SAFETY` outcome без unsafe generation.

## Tested surface

Добавлены focused suites:

- `spec/hostile_openapi_spec.rb` — malformed roots, traversal/broken/recursive
  refs, symlink escape probe, invalid regex, malicious class name и unsafe URL;
- `spec/hostile_openapi_matrix_spec.rb` — invalid version, wrong `paths` type,
  malformed operation, missing schema, giant description, deep schema, XML-only
  media, server variables, cookie parameter, duplicate operations, many
  operations, Unicode/HTML text, invalid pattern, remote ref и invalid pointer.

Результат: 26 adversarial inputs завершились explicit safe outcome; 1 symlink
case отмечен pending, потому что Windows checkout не разрешил создание symlink
без дополнительной OS privilege. Canonical-path guard реализован и проверяется
в коде; traversal escape проходит независимо от symlink privilege.

## Controls

- YAML safe load и JSON parse без object deserialization;
- root document обязан быть object;
- local `$ref` ограничен canonical root directory;
- remote `$ref` запрещён;
- file size limit 10 MiB, resolution depth limit 64, node limit 100,000;
- resolved local files входят в source fingerprint;
- invalid/oversized/suspicious regex блокируется до generated runtime;
- generated class name и server URL проходят safety validation;
- required custom parameters и unsupported auth/media features сохраняются в
  `unsupported_features`, critical values имеют `generation_impact: BLOCKING`.

Machine-readable support policy: [`docs/SUPPORT_MATRIX.md`](../docs/SUPPORT_MATRIX.md).

## Safety result

- Unexpected exceptions in hostile suites: 0.
- Unsafe generation attempts: 0.
- Network fetches for remote refs: 0.
- Silent required-parameter drop: fixed and covered.
- XSS/script text is data; generated Ruby class/URL injection is rejected.
