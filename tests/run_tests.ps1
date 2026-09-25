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
#   - 完整版 luajpp.jar（默认取兄弟仓库 NeLuaJ+Builder/app/libs/luajpp.jar；
#     行为测试需要它，本仓库 app/libs/luajpp_nocglib.jar 仅够语法检查用）
param(
  [string]$Suite,
  [string[]]$Check,
  [string]$Luajpp
)

$ErrorActionPreference = "Stop"
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $testsDir

# ── 定位 luajpp.jar ──
if (-not $Luajpp) {
  $sibling = Join-Path (Split-Path -Parent $root) "NeLuaJ+Builder\app\libs\luajpp.jar"
  if (Test-Path $sibling) {
    $Luajpp = $sibling
  } else {
    $local = Join-Path $root "app\libs\luajpp_nocglib.jar"
    if (Test-Path $local) {
      Write-Warning "未找到完整版 luajpp.jar，回退到 luajpp_nocglib.jar（仅支持 -Check 语法检查）"
      $Luajpp = $local
    }
  }
}
if (-not $Luajpp -or -not (Test-Path $Luajpp)) {
  throw "未找到 luajpp.jar，请用 -Luajpp 指定完整版（NeLuaJ+Builder/app/libs/luajpp.jar）"
}

# ── 增量编译基础设施 ──
$out = Join-Path $testsDir "out"
New-Item -ItemType Directory -Path $out -Force | Out-Null
foreach ($j in @("Run.java", "SyntaxCheck.java")) {
  $srcFile = Join-Path $testsDir $j
  $clsFile = Join-Path $out ($j -replace '\.java$', '.class')
  if (-not (Test-Path $clsFile) -or (Get-Item $srcFile).LastWriteTime -gt (Get-Item $clsFile).LastWriteTime) {
    javac -encoding UTF-8 -cp $Luajpp -d $out $srcFile
  }
}
$cp = "$Luajpp;$out"

# ── 语法检查模式 ──
if ($Check) {
  java -noverify -cp $cp SyntaxCheck @Check
  return
}

# ── 行为测试模式 ──
$suites = @(
  "TestTodo", "TestPatch", "TestRegistry", "TestSubagent",
  "TestParallel", "TestMarkdown", "TestTextUtil", "TestStoreIndex"
)
if ($Suite) { $suites = @($Suite) }

$failed = @()
foreach ($s in $suites) {
  Write-Host "== $s ==" -ForegroundColor Cyan
  $lines = & java -noverify -cp $cp Run (Join-Path $testsDir "$s.lua") 2>&1
  $lines | ForEach-Object { Write-Host "  $_" }
  if ($LASTEXITCODE -ne 0 -or -not (($lines | Out-String) -match "ALL-PASS")) {
    $failed += $s
  }
}

if ($failed.Count -gt 0) {
  Write-Host "FAILED SUITES: $($failed -join ', ')" -ForegroundColor Red
  exit 1
}
Write-Host "ALL SUITES PASS ($($suites.Count))" -ForegroundColor Green
