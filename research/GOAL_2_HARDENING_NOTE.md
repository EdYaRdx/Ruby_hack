# GOAL 2: уточнение границ money и callback

Это clarification реализации внутри frozen pipeline, а не новая architecture.

## Money

`host_amount_to_provider` — единственная conversion, направленная в integer
provider representation. Она использует `BigDecimal` и отклоняет не-exact
result. `provider_amount_to_host` направлена в host major/decimal
representation и возвращает точный `BigDecimal`; fractional major result
допустим. Conversion records Blueprint сохраняют `factor_decimal` для exact
runtime arithmetic; numeric `factor` — только удобная serialized projection.

Для разных representations scale должен быть явным и разрешённым из spec,
`BaseServiceProfile` или case defaults. Conversion record содержит `direction`,
`operation`, `factor` и `scale`. NovaPay получает scale `100` из case default
(`minor`/`kopecks`), а provider со scale `1000` представим без изменения
generic code. Отсутствующий scale означает `REVIEW_REQUIRED` + `BLOCKING`.

## Callback

Terminal callback actions читаются из `BaseServiceProfile.callback_actions`.
Space Payments profile связывает `approved` с `approve_operation`, а `rejected`
с `reject_operation`; у `in_progress` нет terminal action. Если profile не
объявляет terminal action, generated code возвращает явный failure после
signature verification, а не придумывает production host API.
