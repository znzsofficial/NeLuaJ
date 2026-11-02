# Desktop-only regression checks for run_tests.ps1. Uses an isolated temporary
# project and real java/javac; never edits production sources or existing tests.
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("neluaj-runner-" + [guid]::NewGuid().ToString("N"))
$sandboxTests = Join-Path $sandbox "tests"
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-Fixture([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}
function Assert-Runner([string]$Name, [bool]$ShouldPass, [string[]]$RunnerArgs) {
    $previousEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& (Join-Path $PSHOME "pwsh") -NoProfile -File (Join-Path $sandboxTests "run_tests.ps1") @RunnerArgs 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousEAP
    }
    if (($code -eq 0) -ne $ShouldPass) {
        throw "$Name returned $code unexpectedly:`n$($output -join [Environment]::NewLine)"
    }
    Write-Host "PASS $Name (exit $code)"
}
try {
    $assets = Join-Path $sandbox "app/src/main/assets"
    New-Item -ItemType Directory -Path (Join-Path $sandboxTests "libs"), $assets -Force | Out-Null
    foreach ($name in @("run_tests.ps1", "Run.java", "SyntaxCheck.java", "build_maintenance_bootstrap.lua")) {
        Copy-Item (Join-Path $testsDir $name) (Join-Path $sandboxTests $name)
    }
    $jar = Join-Path $sandboxTests "libs/luajpp.jar"
    Copy-Item (Join-Path $testsDir "libs/luajpp.jar") $jar
    Write-Fixture (Join-Path $assets "maintenance_fixture.lua") 'return { ok = true }'
    Write-Fixture (Join-Path $sandboxTests "TestMaintenance.lua") 'assert(require("maintenance_fixture").ok); print("ALL-PASS")'
    Write-Fixture (Join-Path $sandboxTests "TestMaintenanceDiscovery.lua") 'print("ALL-PASS")'
    Assert-Runner "discovery and asset require bootstrap" $true @()
    $valid = Join-Path $sandboxTests "valid.lua"
    $invalid = Join-Path $sandboxTests "invalid.lua"
    Write-Fixture $valid 'return true'
    Write-Fixture $invalid 'local ='
    Assert-Runner "valid syntax" $true @("-Check", $valid)
    Assert-Runner "invalid syntax propagates failure" $false @("-Check", $invalid)
    Write-Fixture (Join-Path $sandboxTests "TestMaintenance.lua") 'print("ALL-PASS"); os.exit(7)'
    Assert-Runner "nonzero test exit overrides pass marker" $false @("-Suite", "TestMaintenance")
    Write-Fixture (Join-Path $sandboxTests "TestMaintenance.lua") 'print("not a pass marker")'
    Assert-Runner "missing pass marker fails" $false @("-Suite", "TestMaintenance")
    Assert-Runner "missing suite fails" $false @("-Suite", "TestMissing")
    # Old driver .class files now exist: a failed javac must not reuse them.
    $badJar = Join-Path $sandboxTests "broken.jar"
    Write-Fixture $badJar 'not a jar'
    Assert-Runner "javac failure stops before stale drivers" $false @("-Luajpp", $badJar, "-Check", $valid)
    Write-Host "ALL BUILD-MAINTENANCE CHECKS PASS"
} finally {
    if (Test-Path $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
