$ErrorActionPreference = 'Stop'
$totals = @{ tests = 0L; failures = 0L; errors = 0L; skipped = 0L }
$reportPaths = @(Get-ChildItem -Path . -Recurse -Filter 'TEST-*.xml' -File |
    Where-Object { $_.FullName -match '[\\/]build[\\/]test-results[\\/]' })
foreach ($reportPath in $reportPaths) {
    [xml]$report = Get-Content -LiteralPath $reportPath.FullName -Raw
    $suite = $report.testsuite
    foreach ($metric in @('tests', 'failures', 'errors', 'skipped')) {
        $totals[$metric] += [long]$suite.GetAttribute($metric)
    }
    Write-Output "$($suite.name): tests=$($suite.tests) failures=$($suite.failures) errors=$($suite.errors) skipped=$($suite.skipped)"
    foreach ($testcase in $suite.testcase) {
        if ($testcase.failure -or $testcase.error) {
            Write-Output "FAILED: $($testcase.classname)::$($testcase.name)"
            foreach ($problem in @($testcase.failure) + @($testcase.error)) {
                if ($problem) { Write-Output $problem.InnerText }
            }
        }
    }
}
$summary = "JUnit totals: tests=$($totals.tests), failures=$($totals.failures), errors=$($totals.errors), skipped=$($totals.skipped). XML files=$($reportPaths.Count)."
Write-Output $summary
if ($env:GITHUB_STEP_SUMMARY) {
    $summary | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8
}
