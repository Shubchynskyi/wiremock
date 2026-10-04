$ErrorActionPreference = 'Stop'
$repositoryPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$jarPaths = @(Get-ChildItem -Path (Join-Path $repositoryPath 'wiremock-standalone/build/libs') -Filter 'wiremock-standalone-*.jar' |
    Where-Object { $_.Name -notmatch '-(sources|javadoc|test-fixtures)\.jar$' })
if ($jarPaths.Count -ne 1) { throw "Expected one standalone JAR, found $($jarPaths.Count)" }
$standaloneJar = $jarPaths[0].FullName
$javaName = if ($IsWindows) { 'java.exe' } else { 'java' }
$javaBinary = Join-Path $env:JAVA_HOME "bin/$javaName"

$archive = [IO.Compression.ZipFile]::OpenRead($standaloneJar)
try {
    $entry = $archive.GetEntry('com/github/tomakehurst/wiremock/keystore')
    if (-not $entry -or $archive.GetEntry('keystore')) {
        throw 'Unexpected default keystore packaging in standalone JAR'
    }
    $stream = $entry.Open()
    try {
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))
        if ($hash -ne 'F233C68CDFEE200B9EDC754F32FB5CC5DB946186BDA88E7E482BDD93C1A55A6F') {
            throw 'Bundled keystore bytes changed'
        }
    } finally { $stream.Dispose() }
} finally { $archive.Dispose() }
Write-Output 'Standalone JAR contains the unchanged keystore at the namespaced path'

$fixtureRoot = Join-Path $env:RUNNER_TEMP ('wiremock-2985-' + [Guid]::NewGuid().ToString('N'))
foreach ($fixtureKind in @('file', 'directory')) {
    $fixturePath = Join-Path $fixtureRoot $fixtureKind
    New-Item -ItemType Directory -Path $fixturePath -Force | Out-Null
    $resourcePath = Join-Path $fixturePath 'keystore'
    if ($fixtureKind -eq 'directory') {
        New-Item -ItemType Directory -Path $resourcePath -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $resourcePath 'application.txt') -Value 'Application resource'
    } else {
        Set-Content -LiteralPath $resourcePath -Value 'Not a Java keystore'
    }
    $stdoutPath = Join-Path $fixturePath 'stdout.log'
    $stderrPath = Join-Path $fixturePath 'stderr.log'
    $process = $null
    try {
        $classpath = $fixturePath + [IO.Path]::PathSeparator + $standaloneJar
        $launchOptions = @{
            FilePath = $javaBinary
            ArgumentList = @('-cp', ('"{0}"' -f $classpath), 'wiremock.Run', '--port', '0', '--https-port', '0', '--disable-banner')
            WorkingDirectory = $repositoryPath
            PassThru = $true
            RedirectStandardOutput = $stdoutPath
            RedirectStandardError = $stderrPath
        }
        if ($IsWindows) { $launchOptions.WindowStyle = 'Hidden' }
        $process = Start-Process @launchOptions
        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        $httpsPort = $null
        while ($stopwatch.Elapsed.TotalSeconds -lt 30) {
            if ($process.HasExited) { throw 'Standalone process exited before startup' }
            if (Test-Path -LiteralPath $stdoutPath) {
                $output = Get-Content -LiteralPath $stdoutPath -Raw
                if ($output -match '(?m)^https-port:\s*(\d+)') {
                    $httpsPort = [int]$Matches[1]
                    break
                }
            }
            Start-Sleep -Milliseconds 200
        }
        if (-not $httpsPort) { throw 'Standalone HTTPS port was not reported' }
        $response = Invoke-WebRequest -Uri "https://localhost:$httpsPort/__admin/mappings" -SkipCertificateCheck -TimeoutSec 10
        if ($response.StatusCode -ne 200) { throw "HTTPS returned $($response.StatusCode)" }
        Write-Output "Conflicting keystore $fixtureKind : HTTPS returned 200 on port $httpsPort"
    } catch {
        foreach ($logPath in @($stdoutPath, $stderrPath)) {
            if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath }
        }
        throw
    } finally {
        if ($process) {
            if (-not $process.HasExited) { Stop-Process -Id $process.Id -ErrorAction Stop }
            $process.Dispose()
        }
    }
}
