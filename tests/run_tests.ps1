# NeLuaJ+ 纯 Lua 模块测试驱动：编译 Run/SyntaxCheck 并运行套件。
#
# 用法（在项目根目录执行）：
#   .\tests\run_tests.ps1                  跑全部行为测试套件
#   .\tests\run_tests.ps1 TestTodo          只跑指定套件
#   .\tests\run_tests.ps1 -Check <file.lua> 对文件（可多个）做语法检查
#   .\tests\run_tests.ps1 -Luajpp <jar>     显式指定 luajpp.jar 路径
#
# 依赖：
#   - JDK（java/javac 在 PATH 上）
#   - luajpp.jar：优先 tests/libs/luajpp.jar（仓库内纯 JSE 精简版），
#     缺失时自动回退兄弟仓库完整版 / 本仓库 nocglib（仅 -Check）
param(
  [string]$Suite,
  [string[]]$Check,
  [string]$Luajpp
)

$ErrorActionPreference = "Stop"
# Native exit codes are checked explicitly, including on PowerShell versions
# where a non-zero exit does not become a terminating error.
$PSNativeCommandUseErrorActionPreference = $false
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $testsDir
# Some Lua suites use TEMP; Unix hosts normally only expose TMPDIR (or neither).
if (-not $env:TEMP) { $env:TEMP = [System.IO.Path]::GetTempPath() }

# ── 定位 luajpp.jar ──
# 优先 tests/libs/luajpp.jar（随仓库分发的纯 JSE 精简版）；
# 其次兄弟仓库 NeLuaJ+Builder 的完整版；
# 最后本仓库 luajpp_nocglib.jar（仅支持 -Check 语法检查）
if (-not $Luajpp) {
  $bundled = Join-Path $testsDir "libs/luajpp.jar"
  $sibling = Join-Path (Split-Path -Parent $root) "NeLuaJ+Builder/app/libs/luajpp.jar"
  if (Test-Path $bundled) {
    $Luajpp = $bundled
  } elseif (Test-Path $sibling) {
    $Luajpp = $sibling
  } else {
    $local = Join-Path $root "app/libs/luajpp_nocglib.jar"
    if (Test-Path $local) {
      Write-Warning "未找到完整版 luajpp.jar，回退到 luajpp_nocglib.jar（仅支持 -Check 语法检查）"
      $Luajpp = $local
    }
  }
}
if (-not $Luajpp -or -not (Test-Path $Luajpp)) {
  throw "未找到 luajpp.jar，请用 -Luajpp 指定完整版（NeLuaJ+Builder/app/libs/luajpp.jar）"
}
Write-Host "luajpp.jar: $Luajpp" -ForegroundColor DarkGray

# ── 编译基础设施 ──
# Always rebuild both small drivers, so changing the JDK/JAR cannot reuse stale
# classes. A failed compile must never fall through to an old .class file.
$out = Join-Path $testsDir "out"
New-Item -ItemType Directory -Path $out -Force | Out-Null
$sources = @((Join-Path $testsDir "Run.java"), (Join-Path $testsDir "SyntaxCheck.java"))
& javac -encoding UTF-8 -cp $Luajpp -d $out @sources
if ($LASTEXITCODE -ne 0) {
  throw "javac failed (exit $LASTEXITCODE); tests were not run."
}
$cp = $Luajpp, $out -join [System.IO.Path]::PathSeparator

# ── 语法检查模式 ──
if ($Check) {
  & java -noverify -cp $cp SyntaxCheck @Check
  if ($LASTEXITCODE -ne 0) {
    throw "Lua syntax check failed (exit $LASTEXITCODE)."
  }
  return
}

# ── 行为测试模式 ──
# Discover every behavioral suite, including TestLayoutTools and future suites.
$suites = @(Get-ChildItem -Path $testsDir -Filter "Test*.lua" -File | Sort-Object Name | ForEach-Object { $_.BaseName })
if ($Suite) { $suites = @($Suite) }
if ($suites.Count -eq 0) { throw "No Lua behavioral suites found in $testsDir" }

$failed = @()
foreach ($s in $suites) {
  Write-Host "== $s ==" -ForegroundColor Cyan
  # Windows PowerShell can treat redirected native stderr as an ErrorRecord.
  # Keep capturing it without obscuring the process exit status.
  $prevEAP = $ErrorActionPreference
  $previousSuitePath = $env:NELUAJ_TEST_SUITE
  try {
    $ErrorActionPreference = "Continue"
    $env:NELUAJ_TEST_SUITE = Join-Path $testsDir "$s.lua"
    $lines = @(& java -noverify -cp $cp Run (Join-Path $testsDir "build_maintenance_bootstrap.lua") 2>&1)
    $testExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $prevEAP
    $env:NELUAJ_TEST_SUITE = $previousSuitePath
  }
  $lines | ForEach-Object { Write-Host "  $_" }
  if ($testExitCode -ne 0 -or -not (($lines | Out-String) -match "(?m)^ALL-PASS\b")) {
    $failed += $s
  }
}

if ($failed.Count -gt 0) {
  Write-Host "FAILED SUITES: $($failed -join ', ')" -ForegroundColor Red
  exit 1
}
Write-Host "ALL SUITES PASS ($($suites.Count))" -ForegroundColor Green
