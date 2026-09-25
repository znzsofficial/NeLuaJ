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
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $testsDir

# ── 定位 luajpp.jar ──
# 优先 tests/libs/luajpp.jar（随仓库分发的纯 JSE 精简版）；
# 其次兄弟仓库 NeLuaJ+Builder 的完整版；
# 最后本仓库 luajpp_nocglib.jar（仅支持 -Check 语法检查）
if (-not $Luajpp) {
  $bundled = Join-Path $testsDir "libs\luajpp.jar"
  $sibling = Join-Path (Split-Path -Parent $root) "NeLuaJ+Builder\app\libs\luajpp.jar"
  if (Test-Path $bundled) {
    $Luajpp = $bundled
  } elseif (Test-Path $sibling) {
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
Write-Host "luajpp.jar: $Luajpp" -ForegroundColor DarkGray

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
