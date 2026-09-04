# Приоритет правил и разрешение конфликтов

Дата: 2026-09-03

## Две разные сущности нельзя смешивать

В compiler есть fact layer и decision layer.

`Facts IR` отвечает на вопрос «что буквально обнаружено в input». Это
append-only слой, который может содержать противоречия. `Decision/Blueprint`
отвечает на вопрос «что можно safely use в adapter». Rule может предложить или
разрешить decision, но никогда не должен переписывать source fact так, будто
provider сообщил что-то другое.

## Классы источников

| Source | Значение | Default authority | Scope |
|---|---|---:|---|
| `SPEC_FACT` | явный structural или textual fact из текущей spec | 100 | current spec fingerprint |
| `CASE_DEFAULT` | semantics для named case, подтверждённые organizer-ом | 90 | case/provider scope, never global |
| `BUILTIN_RULE` | deterministic product rule над facts | 70 | compiler version |
| `HUMAN_RULE` | reusable user rule, явно сохранённое человеком | 80 | declared scope + version |
| `PROVIDER_OVERRIDE` | provider-specific explicit correction/configuration | 85 | provider + spec family/fingerprint |
| `HEURISTIC` | weak candidate по сходству имени/prose | 20 | candidate only |

Authority не равна истинности proposition. Один explicit spec fact может быть
противоречив другому explicit spec fact; это conflict, а не основание выбрать
первый. `HEURISTIC` может ранжировать candidates, но не может разрешить
critical conflict.

`BASE_SERVICE_PROFILE` и `ADAPTER_POLICY` — намеренно раздельные labels для
target-system facts и adapter choices. Это не provider evidence: первая label
описывает сторону Space Payments в mapping, вторая — намеренное поведение,
например always sending an optional header. Ни одна из labels не может
переписывать OpenAPI `required` fact.

## Процедура разрешения приоритетов

1. Parse и validate input; записать source fingerprint и каждый relevant fact с
   JSON Pointer/source location.
2. Resolve `$ref` и normalize shapes, не придумывая business meaning.
3. Собрать candidates из built-in rules, case defaults, human rules и provider
   overrides. Каждый candidate содержит source, scope и rule version.
4. Проверить scope и freshness. Rule за пределами declared scope игнорируется и
   фиксируется в отчёте. Override с несовпадающим spec fingerprint — это
   `STALE_OVERRIDE`, а не текущий ответ.
5. Сгруппировать candidates по decision key, например `money.amount_unit` или
   `operation.create.provider_path`.
6. При конфликте текущих `SPEC_FACT` выдать `CONFLICT` и остановить resolution
   для затронутого key.
7. Иначе выбрать applicable explicit candidate с наибольшей authority. Более
   низкий source может заполнить missing key, но не может молча заменить более
   высокий source.
8. Если human/provider rule переопределяет current explicit fact, сохранить
   fact, показать override и потребовать explicit confirmation для critical keys.
9. Heuristic может дать только `REVIEW_REQUIRED`; она никогда не может дать
   `ACCEPT` для critical semantic key.
10. Валидировать resolved Blueprint. Любой unresolved critical key становится
    `BLOCKING`; non-critical unknowns остаются видимыми в `unknowns`.

## Матрица конфликтов

| Higher vs lower | Result |
|---|---|
| `SPEC_FACT` vs `BUILTIN_RULE` | spec fact wins if non-conflicting; rule is explanatory |
| `SPEC_FACT` vs `CASE_DEFAULT` | current explicit spec fact wins; case default becomes conflict/review |
| `SPEC_FACT` vs `HUMAN_RULE` | fact remains; human choice is an explicit override requiring confirmation |
| `SPEC_FACT` vs `PROVIDER_OVERRIDE` | provider override can change generated decision only when scoped, fresh and explicitly accepted |
| `SPEC_FACT` vs `HEURISTIC` | spec fact wins; heuristic discarded or shown as weak candidate |
| `CASE_DEFAULT` vs `BUILTIN_RULE` | case default wins within the named case |
| `CASE_DEFAULT` vs `HUMAN_RULE` | human rule may override for this provider if explicitly confirmed |
| `PROVIDER_OVERRIDE` vs `HUMAN_RULE` | explicit human choice wins for its narrower matching scope; log both |
| any explicit source vs `HEURISTIC` | explicit source wins |
| two same-level explicit sources | conflict; no arbitrary tie-break |

Ключевое safety rule: override может изменить decision, но не может стереть
противоречивый fact или сделать старый spec fingerprint текущим.

## Freshness и scope

Минимальный freshness tuple:

```text
spec_fingerprint = SHA256(root document + full resolved local-ref closure
                           + resolver policy)
rule_scope = provider identity + operation/field selector
rule_version = compiler/rule-set version
```

Override является stale, если его записанный `spec_fingerprint` отличается от
current fingerprint для любого fact, от которого override зависит. Даже
косметическое изменение может invalidировать fingerprint; review UI может
позволить человеку подтвердить его заново, но generation не должен молча
переиспользовать override.

Reusable rules должны быть уже, чем «all payment providers». Безопасный пример:
«если schema property называется `amount`, а для current provider family
подтверждены kopecks, предложить minor units». Небезопасные примеры: «all
amounts are kopecks» или «all signatures are hex».

## Pseudocode разрешения

```text
facts = ingest_to_facts(input, fingerprint)
candidates = analyze(facts) + scoped_rules(facts)

for key in decision_keys(candidates):
  if has_conflicting_spec_facts(key):
    decision[key] = REVIEW_REQUIRED(conflict=true)
    continue
  applicable = fresh_and_in_scope(candidates[key])
  if applicable contains stale_override:
    decision[key] = BLOCKING(STALE_OVERRIDE)
    continue
  winner = highest_authority_explicit(applicable)
  if winner is absent:
    decision[key] = UNKNOWN
  else if winner.source == HEURISTIC and key is critical:
    decision[key] = REVIEW_REQUIRED
  else:
    decision[key] = ACCEPT or REVIEW_REQUIRED according to confirmation state
```

## Применение к NovaPay

Для этого case YAML предоставляет endpoint/auth/schema facts. Organizer Q&A
предоставляет semantics `CASE_DEFAULT`: kopecks, SBP `bank_code`, raw-body
HMAC-SHA256 to hex в `X-NovaPay-Signature`, logical `request_method` и status
fallback map. Эти значения могут разрешить case Blueprint, но должны быть
помечены как case provenance, а не ошибочно приписаны OpenAPI file.
