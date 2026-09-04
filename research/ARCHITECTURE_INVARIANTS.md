# Архитектурные инварианты

Дата: 2026-09-03

Это обязательные свойства proposed compiler. Изменение, нарушающее один из
инвариантов, требует architecture review, а не только нового template.

1. **Facts не являются inferences.** Structural facts сохраняют source locations и никогда не перезаписываются mapping decision.
2. **Semantics не находятся в templates.** ERB только проецирует resolved Blueprint и не решает, что означает create, money, status или callback.
3. **Blueprint — граница generator.** Ruby, docs, fixtures, previews и readiness являются проекциями одной validated Blueprint.
4. **Критический смысл нельзя молча угадывать.** Unknown или conflicting money, auth, status, webhook и host-action semantics блокируют затронутую generation.
5. **Unknown сохраняются.** Unsupported constructs, extra endpoints и unresolved fields остаются доступными для inspection, а не удаляются.
6. **У каждого решения есть provenance.** Минимум: source class, locations, rule version, scope, evidence и conflicts.
7. **Heuristics только предлагают.** Lexical/fuzzy similarity может ранжировать candidate, но не может принять critical semantic mapping.
8. **Overrides имеют scope и freshness.** Provider override содержит provider, selector, spec fingerprint и rule version; stale override нельзя переиспользовать.
9. **Precedence явен.** Conflicts одного уровня не разрешаются порядком итерации или hash order.
10. **Raw webhook input — first-class.** Signature verification получает точный raw body до JSON parsing или normalization.
11. **Money representation и unit разделены.** Integer, decimal string и major/minor units являются независимыми facts/decisions.
12. **Logical host action отделено от HTTP method.** `request_method` связывается только через подтверждённый `BaseServiceProfile`.
13. **Profile compatibility проверяема.** Test stub может заменить отсутствующий host, но generated compatibility не заявляется без profile contract и executable checks.
14. **Generation детерминирована.** Одинаковые resolved Blueprint и generator version дают byte-stable outputs.
15. **Manual edits не меняют generated source.** Human decisions обновляют review manifest/overrides; regeneration пересоздаёт projections.
16. **CLI и UI используют одно core.** UI является только проекцией manifests и не вводит второй mapping engine.
17. **Verification предшествует readiness claims.** Успешный parse не означает успешную integration; readiness вычисляется после generation и executable checks.
18. **Benchmark labels не являются implementation evidence.** Policy-emulator results остаются policy tests, пока не выполнен real generated Ruby.
19. **Case defaults не являются universal facts.** `CASE_DEFAULT` ограничен указанным case/provider и не может молча стать global.
20. **Compiler работает fail-closed для затронутых paths.** Неоднозначный webhook не стирает valid balance endpoint, но не позволяет заявить verified webhook adapter.

## Точки проверки инвариантов

Первая test suite должна содержать fixtures для каждого пункта, особенно для
facts-vs-decisions, stale fingerprint, raw-body HMAC, amount-unit variants,
ambiguous operations, extra operation retention и deterministic regeneration.
