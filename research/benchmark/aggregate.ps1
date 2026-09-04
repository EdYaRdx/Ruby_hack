param(
  [string]$ResultsFile = (Join-Path (Split-Path $PSScriptRoot -Parent) '..\tmp\benchmark\results.json')
)

$ErrorActionPreference = 'Stop'
$resolved = if ([System.IO.Path]::IsPathRooted($ResultsFile)) {
  [System.IO.Path]::GetFullPath($ResultsFile)
} else {
  [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $ResultsFile))
}
if (-not (Test-Path -LiteralPath $resolved)) {
  throw "Real benchmark results not found: $resolved. Run: bundle exec ruby research/benchmark/run.rb"
}

$report = Get-Content -Raw -Encoding UTF8 -LiteralPath $resolved | ConvertFrom-Json
Write-Output ("Real benchmark: {0}/{1} passed; decision_accuracy={2}%; safe_decision_coverage={3}%; automatic_accept_rate={4}%; semantic_accept_accuracy={5}%; critical_false_accepts={6}; review={7}%; unknown={8}%" -f `
  $report.aggregate.cases_passed,
  $report.aggregate.cases_total,
  $report.aggregate.decision_accuracy,
  $report.aggregate.safe_decision_coverage,
  $report.aggregate.automatic_accept_rate,
  $report.aggregate.semantic_accept_accuracy,
  $report.aggregate.critical_false_accept_count,
  $report.aggregate.review_required_rate,
  $report.aggregate.unknown_rate)
Write-Output ("semantic: operation={0}%; money={1}%; status={2}%; auth={3}%; webhook={4}%; idempotency={5}%; fields={6}%" -f `
  $report.aggregate.operation_semantic_accuracy,
  $report.aggregate.money_semantic_accuracy,
  $report.aggregate.status_semantic_accuracy,
  $report.aggregate.auth_semantic_accuracy,
  $report.aggregate.webhook_semantic_accuracy,
  $report.aggregate.idempotency_semantic_accuracy,
  $report.aggregate.field_mapping_semantic_accuracy)
Write-Output ("generation_success_rate={0}%; generated_syntax_pass_rate={1}%; disputed_cases={2}; legacy_decision_only_automatic_coverage={3}%" -f `
  $report.aggregate.generation_success_rate,
  $report.aggregate.generated_syntax_pass_rate,
  $report.aggregate.disputed_case_count,
  $report.aggregate.legacy_decision_only_automatic_coverage)
if ([int]$report.aggregate.critical_false_accept_count -gt 0) {
  exit 1
}
