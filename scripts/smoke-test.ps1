param(
  [switch]$KeepTemp
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$TempRoot = Join-Path $env:TEMP ("a-brain-smoke-" + [guid]::NewGuid().ToString())

function Invoke-SmokeCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$File,

    [string[]]$Arguments = @(),

    [int]$ExpectedExitCode = 0
  )

  $Display = ($File + " " + ($Arguments -join " ")).Trim()
  $ArgumentList = @($Arguments | ForEach-Object {
    $Value = [string]$_
    if ($Value -match '[\s"]') {
      '"' + ($Value -replace '"', '\"') + '"'
    } else {
      $Value
    }
  })
  Write-Output ("[run] {0}" -f $Display)
  $StdoutFile = Join-Path $env:TEMP ("a-brain-smoke-stdout-" + [guid]::NewGuid().ToString() + ".txt")
  $StderrFile = Join-Path $env:TEMP ("a-brain-smoke-stderr-" + [guid]::NewGuid().ToString() + ".txt")

  try {
    $StartParams = @{
      FilePath = $File
      NoNewWindow = $true
      Wait = $true
      PassThru = $true
      RedirectStandardOutput = $StdoutFile
      RedirectStandardError = $StderrFile
    }
    if ($ArgumentList.Count -gt 0) {
      $StartParams.ArgumentList = $ArgumentList
    }

    $Process = Start-Process @StartParams
    $ExitCode = $Process.ExitCode
    $Output = @()
    if (Test-Path -LiteralPath $StdoutFile) {
      $Output += Get-Content -LiteralPath $StdoutFile -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $StderrFile) {
      $Output += Get-Content -LiteralPath $StderrFile -ErrorAction SilentlyContinue
    }
  } finally {
    Remove-Item -LiteralPath $StdoutFile, $StderrFile -Force -ErrorAction SilentlyContinue
  }

  if ($Output) {
    $Output | Select-Object -First 8 | ForEach-Object { Write-Output ("  " + $_) }
  }

  if ($ExitCode -ne $ExpectedExitCode) {
    throw "Command exit code $ExitCode, expected ${ExpectedExitCode}: $Display"
  }

  return [pscustomobject]@{
    command = $Display
    exitCode = $ExitCode
  }
}

function Assert-JsonParse {
  param([string]$BasePath)

  Get-ChildItem -LiteralPath $BasePath -Recurse -Filter "*.json" | ForEach-Object {
    Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null
  }
}

function Assert-OnlyGitkeep {
  param([string[]]$Paths)

  foreach ($PathValue in $Paths) {
    if (-not (Test-Path -LiteralPath $PathValue)) {
      continue
    }

    $Dirty = Get-ChildItem -LiteralPath $PathValue -Force | Where-Object { $_.Name -ne ".gitkeep" }
    if ($Dirty) {
      throw ("Expected only .gitkeep under {0}; found {1}" -f $PathValue, (($Dirty | Select-Object -ExpandProperty Name) -join ", "))
    }
  }
}

Write-Output "A-Brain smoke test"
Write-Output ("source root: {0}" -f $Root)
Write-Output ("temp root: {0}" -f $TempRoot)

Copy-Item -LiteralPath $Root -Destination $TempRoot -Recurse -Force

try {
  Push-Location $TempRoot

  New-Item -ItemType Directory -Force -Path `
    ".\library\sources", `
    ".\knowledge\notes", `
    ".\knowledge\processes", `
    ".\knowledge\skills" | Out-Null

  @"
---
title: Smoke Source
sourceId: smoke-source
sourceType: markdown
sourcePath: library/sources/smoke-source.md
sourceQuality: primary
---

# Smoke Source

This public sample explains a reusable local memory workflow for A-Brain.
"@ | Set-Content -LiteralPath ".\library\sources\smoke-source.md" -Encoding UTF8

  @"
---
title: Smoke Note
type: note
tags: [smoke]
source: local
updated: 2026-06-25
summary: Smoke note for release verification.
status: fresh
confidenceScore: 50
confidenceFormulaVersion: a-brain-confidence-v1
confidenceAggregation: p25
claimSetPath:
confidenceClaimRefs: []
provenanceState: imported
inferenceState: direct
citationCoverage: partial
reviewState: draft
schemaState: compliant
sourceIds: [smoke-source]
contradictedBy: []
supersedes: []
promoted_to:
reviewQueueRefs: []
modelId:
promptVersion:
contentHash:
sourceHashes: []
---

# Smoke Note

Use A-Brain to record task events, search local knowledge, and maintain reviewable memory.
"@ | Set-Content -LiteralPath ".\knowledge\notes\smoke-note.md" -Encoding UTF8

  @"
---
title: Smoke Process
type: process
tags: [smoke]
source: local
updated: 2026-06-25
summary: Smoke process for release verification.
status: fresh
confidenceScore: 50
confidenceFormulaVersion: a-brain-confidence-v1
confidenceAggregation: p25
claimSetPath:
confidenceClaimRefs: []
provenanceState: imported
inferenceState: direct
citationCoverage: partial
reviewState: draft
schemaState: compliant
sourceIds: [smoke-source]
contradictedBy: []
supersedes: []
promoted_to:
reviewQueueRefs: []
modelId:
promptVersion:
contentHash:
sourceHashes: []
---

# Smoke Process

1. Write diary events.
2. Refresh think indexes.
3. Run dream maintenance when needed.
"@ | Set-Content -LiteralPath ".\knowledge\processes\smoke-process.md" -Encoding UTF8

  Invoke-SmokeCommand ".\scripts\diary-event.cmd" @("-Type", "task_start", "-Summary", "Smoke test start") | Out-Null
  Invoke-SmokeCommand ".\scripts\diary-event.cmd" @("-Type", "think_query", "-Summary", "Smoke think query") | Out-Null
  Invoke-SmokeCommand ".\scripts\diary-query.cmd" @("-Limit", "5") | Out-Null
  Invoke-SmokeCommand ".\scripts\diary-derive.cmd" | Out-Null

  Invoke-SmokeCommand ".\scripts\think-refresh.cmd" | Out-Null
  Invoke-SmokeCommand ".\scripts\think-query.cmd" @("-Mode", "brief", "local memory workflow") | Out-Null
  Invoke-SmokeCommand ".\scripts\think-health.cmd" | Out-Null

  Invoke-SmokeCommand ".\scripts\ingest-library.cmd" @("-SourcePath", ".\library\sources\smoke-source.md") | Out-Null
  Invoke-SmokeCommand ".\scripts\dream-lint.cmd" | Out-Null
  Invoke-SmokeCommand ".\scripts\dream-review.cmd" @("-Report") | Out-Null
  Invoke-SmokeCommand ".\scripts\dream-maintain.cmd" | Out-Null

  Invoke-SmokeCommand ".\scripts\learn-candidate.cmd" @("-InputPath", ".\knowledge\notes\smoke-note.md", "-InputType", "note") | Out-Null
  $Candidate = Get-ChildItem -LiteralPath ".\learn\candidates" -Filter "*.md" | Select-Object -First 1
  if (-not $Candidate) {
    throw "learn-candidate did not create a candidate markdown file."
  }

  Invoke-SmokeCommand ".\scripts\learn-promote.cmd" @("-Candidate", $Candidate.FullName, "-Decision", "promoted") | Out-Null
  Invoke-SmokeCommand ".\scripts\learn-promote.cmd" @("-Candidate", $Candidate.FullName, "-Decision", "promoted", "-InstallRuntime") -ExpectedExitCode 1 | Out-Null

  if (Test-Path -LiteralPath ".\learn\reviews") {
    throw "learn/reviews should not exist."
  }

  if (Test-Path -LiteralPath ".\.codex\skills") {
    throw ".codex/skills should not be created."
  }

  Assert-JsonParse -BasePath $TempRoot

  Pop-Location

  Assert-OnlyGitkeep -Paths @(
    (Join-Path $Root "diary\events"),
    (Join-Path $Root "diary\turns"),
    (Join-Path $Root "diary\sessions"),
    (Join-Path $Root "ingest\runs"),
    (Join-Path $Root "ingest\manifests"),
    (Join-Path $Root "think\indexes"),
    (Join-Path $Root "think\reports"),
    (Join-Path $Root "dream\reports"),
    (Join-Path $Root "dream\review\reports"),
    (Join-Path $Root "dream\lint"),
    (Join-Path $Root "dream\correction"),
    (Join-Path $Root "learn\candidates"),
    (Join-Path $Root "learn\promoted"),
    (Join-Path $Root "knowledge\skills")
  )

  Write-Output "A-Brain smoke test passed."
  Write-Output ("temp root: {0}" -f $TempRoot)
} finally {
  if ((Get-Location).Path -eq $TempRoot) {
    Pop-Location
  }

  if (-not $KeepTemp -and (Test-Path -LiteralPath $TempRoot)) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
  }
}
