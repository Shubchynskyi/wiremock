$ErrorActionPreference = 'Stop'
$serialInitPath = Join-Path $env:RUNNER_TEMP 'wiremock-2985-serial.init.gradle'
@'
gradle.projectsEvaluated {
    gradle.rootProject.allprojects {
        tasks.withType(org.gradle.api.tasks.testing.Test).configureEach {
            maxParallelForks = 1
        }
    }
}
'@ | Set-Content -LiteralPath $serialInitPath -Encoding utf8

$selectedTasks = @($env:WIREMOCK_GRADLE_TASKS -split '\s+' | Where-Object { $_ })
if ($selectedTasks.Count -eq 0) { throw 'No Gradle task selected' }
$gradleArguments = [Collections.Generic.List[string]]::new()
foreach ($selectedTask in $selectedTasks) { $gradleArguments.Add($selectedTask) }
foreach ($testFilter in ($env:WIREMOCK_TEST_FILTERS -split ',')) {
    if ($testFilter.Trim()) {
        $gradleArguments.Add('--tests')
        $gradleArguments.Add($testFilter.Trim())
    }
}
foreach ($argument in @('--init-script', $serialInitPath, '--no-parallel', '--max-workers=2', '--console=plain', '--stacktrace', '--no-daemon')) {
    $gradleArguments.Add($argument)
}
java -version
if ($IsWindows) {
    & ./gradlew.bat @gradleArguments
} else {
    & chmod +x ./gradlew
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & ./gradlew @gradleArguments
}
exit $LASTEXITCODE
