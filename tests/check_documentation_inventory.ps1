# Read-only inventory checks. Never dot-source/evaluate application or runner code.
# Run from any directory: pwsh -File tests/check_documentation_inventory.ps1
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = [System.IO.Path]::GetFullPath($Root)
$issues = [System.Collections.Generic.List[string]]::new()
$checkedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

function Read-RepositoryText([string]$RelativePath) {
  $path = Join-Path $Root $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Required inventory input missing: $RelativePath"
  }
  return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Get-MarkedSection([string]$Text, [string]$Name) {
  $pattern = '(?s)<!-- ' + [regex]::Escape($Name) + ':start -->(.*?)<!-- ' + [regex]::Escape($Name) + ':end -->'
  $matches = [regex]::Matches($Text, $pattern)
  if ($matches.Count -ne 1) { throw "Expected exactly one marked section: $Name" }
  return $matches[0].Groups[1].Value
}

function Compare-Inventory([string]$Label, [string[]]$Expected, [string[]]$Actual) {
  if ($Expected.Count -eq 0 -or $Actual.Count -eq 0) {
    $issues.Add("${Label}: empty inventory; update the static extractor, never execute source as a fallback")
    return
  }
  foreach ($side in @(@{ Name = 'source'; Items = $Expected }, @{ Name = 'documented'; Items = $Actual })) {
    foreach ($duplicate in @($side.Items | Group-Object | Where-Object Count -gt 1)) {
      $issues.Add("${Label}: duplicate $($side.Name) entry $($duplicate.Name)")
    }
  }
  foreach ($item in $Expected) {
    if ($Actual -cnotcontains $item) { $issues.Add("${Label}: missing entry $item") }
  }
  foreach ($item in $Actual) {
    if ($Expected -cnotcontains $item) { $issues.Add("${Label}: stale/extra entry $item") }
  }
}

function Check-FileReference([string]$Document, [string]$RelativePath) {
  if ($checkedPaths.Add("$Document|$RelativePath")) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $RelativePath) -PathType Leaf)) {
      $issues.Add("${Document}: missing file $RelativePath")
    }
  }
}

$documents = @('README.md', 'README_CN.md', 'docs/README.md', 'docs/BUILDING.md',
  'docs/MAINTENANCE.md', 'docs/HOME.md', 'docs/HOME_VALIDATION.md', 'docs/PROJECT_TEMPLATES.md',
  'docs/AIAgent.md', 'docs/AGENT_REFACTORING_MASTER.md', 'docs/LuaLayout.md',
  'docs/LuaActivity.md', 'docs/LuaJRuntime.md', 'docs/BuilderHandoff.md',
  'tests/README.md', 'app/libs/README.md')
$texts = @{}
foreach ($document in $documents) {
  $text = Read-RepositoryText $document
  $texts[$document] = $text
  # Only explicit inline file paths, not API names, globs, examples with placeholders or directories.
  foreach ($match in [regex]::Matches($text, '`((?:app/|mods/|activities/|res/|tests/|com/)[A-Za-z0-9_+$./-]+\.(?:lua|kt|java|md|html|ps1|kts|xml|jar))`')) {
    $reference = $match.Groups[1].Value
    if ($reference.StartsWith('mods/') -or $reference.StartsWith('res/') -or $reference.StartsWith('activities/')) {
      $reference = 'app/src/main/assets/' + $reference
    } elseif ($reference.StartsWith('com/')) {
      $reference = 'app/src/main/java/' + $reference
    }
    Check-FileReference $document $reference
  }
  foreach ($match in [regex]::Matches($text, '\[[^\]]+\]\(([^)\s#]+)(?:#[^)]*)?\)')) {
    $link = $match.Groups[1].Value
    if ($link -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or $link.StartsWith('/')) { continue }
    $directory = Split-Path -Parent $document
    $reference = if ($directory) { Join-Path $directory $link } else { $link }
    Check-FileReference $document $reference
  }
}

$suiteSection = Get-MarkedSection $texts['tests/README.md'] 'test-suites'
$documentedSuites = @([regex]::Matches($suiteSection, '(?m)^\|\s*(Test[A-Za-z0-9_]+)\s*\|') | ForEach-Object { $_.Groups[1].Value })
$suiteFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'tests') -Filter 'Test*.lua' -File | ForEach-Object { $_.BaseName })
$runner = Read-RepositoryText 'tests/run_tests.ps1'
# The runner is read as text, never invoked. Recognize the explicit discovery
# convention or a legacy literal list; unknown formats fail closed.
$registration = [regex]::Matches($runner, '(?ms)^\$suites\s*=\s*@\((.*?)^\)')
if ($registration.Count -eq 1) {
  $registeredSuites = @([regex]::Matches($registration[0].Groups[1].Value, '"(Test[A-Za-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value })
} elseif ($runner -match '(?m)^\$suites = @\(Get-ChildItem -Path \$testsDir -Filter "Test\*\.lua" -File \| Sort-Object Name \| ForEach-Object \{ \$_\.BaseName \}\)\r?$') {
  $registeredSuites = $suiteFiles
} else {
  throw 'Unrecognized suite registration/discovery format; update the inventory extractor'
}
Compare-Inventory 'Suite files vs README' $suiteFiles $documentedSuites
Compare-Inventory 'Runner registration vs suite files' $suiteFiles $registeredSuites

$toolSection = Get-MarkedSection $texts['docs/AIAgent.md'] 'builtin-tools'
$documentedTools = @([regex]::Matches($toolSection, '`([a-z][a-z0-9_]*)`') | ForEach-Object { $_.Groups[1].Value })
$schemas = Read-RepositoryText 'app/src/main/assets/mods/agent/ToolRegistry.lua'
# Match only literal function schema headers, not arbitrary name properties or prose.
$declaredTools = @([regex]::Matches($schemas, '\["function"\]\s*=\s*\{\s*name\s*=\s*"([a-z][a-z0-9_]*)"') | ForEach-Object { $_.Groups[1].Value })
Compare-Inventory 'Tool schema vs AIAgent table' $declaredTools $documentedTools

$layoutSection = [regex]::Match($texts['docs/LuaLayout.md'], '(?s)## 3\..*?(?=## 4\.)').Value
$documentedLayout = @([regex]::Matches($layoutSection, '(?m)^\s*(Layout[A-Za-z0-9_]+\.kt)\s+--') | ForEach-Object { $_.Groups[1].Value })
$layoutFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'app/src/main/java/com/androlua/layout') -Filter '*.kt' -File | ForEach-Object { $_.Name })
Compare-Inventory 'Layout modules vs LuaLayout inventory' $layoutFiles $documentedLayout

# Keep the bundled API catalog complete, including support files. Read declarations
# as text; neither HTML scripts nor the Lua help catalog are executed here.
$bundledRoot = Join-Path $Root 'app/src/main/assets/res/doc'
$catalogText = Read-RepositoryText 'app/src/main/assets/res/doc/agent_docs.md'
$catalogFiles = @([regex]::Matches($catalogText, '`res/doc/([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
$bundledFiles = @(Get-ChildItem -LiteralPath $bundledRoot -File -Recurse | ForEach-Object {
  $_.FullName.Substring($bundledRoot.Length).TrimStart([char[]]'\/').Replace('\', '/')
})
Compare-Inventory 'Bundled docs vs Agent catalog' $bundledFiles $catalogFiles

foreach ($html in @(Get-ChildItem -LiteralPath $bundledRoot -Filter '*.html' -File)) {
  $text = [System.IO.File]::ReadAllText($html.FullName, [System.Text.Encoding]::UTF8)
  foreach ($match in [regex]::Matches($text, '(?i)<[a-z][^>]*?\b(?:href|src)\s*=\s*["'']([^"'']+)["'']')) {
    $link = $match.Groups[1].Value
    if ($link.StartsWith('#') -or $link -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or $link.StartsWith('//')) { continue }
    $relative = ($link -split '[?#]', 2)[0]
    if ($relative -eq '') { continue }
    $target = Join-Path $html.DirectoryName $relative
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
      $issues.Add("$($html.Name): missing bundled link $relative")
    }
  }
}

$helpCatalog = Read-RepositoryText 'app/src/main/assets/mods/help/DocCatalog.lua'
foreach ($match in [regex]::Matches($helpCatalog, 'file\s*=\s*"([^"]+)"\s*\.\.\s*docLanguage\s*\.\.\s*"([^"]+)"|file\s*=\s*"([^"\r\n]+\.html)"')) {
  $files = if ($match.Groups[3].Success) { @($match.Groups[3].Value) } else {
    @(($match.Groups[1].Value + 'zh' + $match.Groups[2].Value), ($match.Groups[1].Value + 'en' + $match.Groups[2].Value))
  }
  foreach ($file in $files) {
    Check-FileReference 'Help catalog' ('app/src/main/assets/res/doc/' + $file)
  }
}

# Every maintainer document has a deliberate entry; history may remain in place.
$indexedDocs = @([regex]::Matches($texts['docs/README.md'], '\]\(\./([^)#]+\.md)(?:#[^)]*)?\)') |
  ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$maintainerDocs = @(Get-ChildItem -LiteralPath (Join-Path $Root 'docs') -Filter '*.md' -File |
  Where-Object Name -ne 'README.md' | ForEach-Object { $_.Name })
Compare-Inventory 'Maintainer docs vs main index' $maintainerDocs $indexedDocs

$buildScript = Read-RepositoryText 'app/build.gradle.kts'
$sdkPatterns = @{
  compileSdk = '(?s)compileSdk\s*\{\s*version\s*=\s*release\((\d+)\)'
  targetSdk = '\btargetSdk\s*=\s*(\d+)'
  minSdk = '\bminSdk\s*=\s*(\d+)'
}
foreach ($name in $sdkPatterns.Keys) {
  $sdk = [regex]::Match($buildScript, $sdkPatterns[$name])
  if (-not $sdk.Success) { throw "Unrecognized $name declaration; update the SDK inventory extractor" }
  if ($texts['docs/BUILDING.md'] -notmatch ([regex]::Escape($name) + '\s*=\s*' + $sdk.Groups[1].Value + '\b')) {
    $issues.Add("BUILDING.md: synchronize $name with app/build.gradle.kts")
  }
}

# Prohibit brittle handwritten suite/assertion/builtin-tool totals, not behavioral limits.
foreach ($document in @('README.md', 'README_CN.md', 'tests/README.md', 'docs/AIAgent.md')) {
  if ($texts[$document] -match '\d+\s*\u4e2a(?:\u5957\u4ef6|\u65ad\u8a00|\u5185\u7f6e\u5de5\u5177)' -or
      $texts[$document] -match '(?i)\b\d+\+?\s+(?:built-in tools|suites|assertions)\b') {
    $issues.Add("${document}: remove handwritten suite/assertion/builtin-tool totals")
  }
  if ($texts[$document] -match 'img\.shields\.io/badge/build-passing') {
    $issues.Add("${document}: use a real workflow status badge, not a fixed passing label")
  }
}

if ($issues.Count -gt 0) {
  foreach ($issue in $issues) { Write-Host "FAIL: $issue" }
  Write-Host "Documentation inventory failed ($($issues.Count) issues)."
  exit 1
}
Write-Host "ALL-PASS: documentation inventory ($($suiteFiles.Count) suites, $($declaredTools.Count) tools, $($layoutFiles.Count) layout modules, $($checkedPaths.Count) file references)."
Write-Host 'Inventory only: no application code executed; behavior and Android/device validation remain separate.'
