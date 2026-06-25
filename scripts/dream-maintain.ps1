param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$ReportDir = Join-Path $Root "dream/reports"
$ThinkHealthReport = Join-Path $Root "think/reports/health-report.json"
$DreamLintReport = Join-Path $Root "dream/lint/lint-report.json"
$DreamReviewState = Join-Path $Root "dream/review/state.json"

function Get-UniqueReportFile {
  param(
    [string]$Directory,
    [string]$Prefix
  )

  $Timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss-fff")
  $Candidate = Join-Path $Directory ("{0}-{1}.md" -f $Prefix, $Timestamp)
  if (-not (Test-Path -LiteralPath $Candidate)) {
    return $Candidate
  }

  $Suffix = 2
  while ($true) {
    $WithSuffix = Join-Path $Directory ("{0}-{1}-{2}.md" -f $Prefix, $Timestamp, $Suffix)
    if (-not (Test-Path -LiteralPath $WithSuffix)) {
      return $WithSuffix
    }
    $Suffix += 1
  }
}

function Get-JsonFile {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  try {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Add-CommandSection {
  param(
    [System.Collections.Generic.List[string]]$Lines,
    [string]$Title,
    [string[]]$Output
  )

  $Lines.Add("## $Title") | Out-Null
  $Lines.Add("") | Out-Null
  $Lines.Add('```text') | Out-Null
  if ($null -eq $Output -or $Output.Count -eq 0) {
    $Lines.Add("(no output)") | Out-Null
  } else {
    foreach ($Line in $Output) {
      $Lines.Add([string]$Line) | Out-Null
    }
  }
  $Lines.Add('```') | Out-Null
  $Lines.Add("") | Out-Null
}

New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

$GeneratedAt = (Get-Date).ToString("o")
$RefreshOutput = @(& (Join-Path $PSScriptRoot "think-refresh.ps1"))
$HealthOutput = @(& (Join-Path $PSScriptRoot "think-health.ps1"))
$LintOutput = @(& (Join-Path $PSScriptRoot "dream-lint.ps1"))
$ReviewOutput = & (Join-Path $PSScriptRoot "dream-review.ps1") -Report
$ReviewOutput = @($ReviewOutput)

$HealthReport = Get-JsonFile -Path $ThinkHealthReport
$LintReport = Get-JsonFile -Path $DreamLintReport
$ReviewState = Get-JsonFile -Path $DreamReviewState
$ReportFile = Get-UniqueReportFile -Directory $ReportDir -Prefix "dream-maintain"

$Lines = New-Object System.Collections.Generic.List[string]
$Lines.Add("# A-Brain Dream Maintain Report") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("- Generated: $GeneratedAt") | Out-Null
$Lines.Add("- Apply: false") | Out-Null
$Lines.Add("") | Out-Null

if ($null -ne $HealthReport) {
  $Lines.Add("## Health Summary") | Out-Null
  $Lines.Add("") | Out-Null
  $Lines.Add("- sourceCoverage.librarySourceCount: $($HealthReport.sourceCoverage.librarySourceCount)") | Out-Null
  $Lines.Add("- sourceCoverage.coverageRatio: $($HealthReport.sourceCoverage.sourceMarkerStats.coverageRatio)") | Out-Null
  $Lines.Add("- indexFreshness.indexableFileCount: $($HealthReport.indexFreshness.indexableFileCount)") | Out-Null
  $Lines.Add("- reviewBacklog.pending_human_review: $($HealthReport.reviewBacklog.pending_human_review)") | Out-Null
  $Lines.Add("- querySaveRate.ratio: $($HealthReport.querySaveRate.ratio)") | Out-Null
  $Lines.Add("") | Out-Null
}

if ($null -ne $LintReport) {
  $Lines.Add("## Lint Summary") | Out-Null
  $Lines.Add("") | Out-Null
  $Lines.Add("- issueCount: $($LintReport.issueCount)") | Out-Null
  $CountsJson = ($LintReport.countsByType | ConvertTo-Json -Compress)
  $Lines.Add("- countsByType: $CountsJson") | Out-Null
  $Lines.Add("") | Out-Null
}

if ($null -ne $ReviewState) {
  $Lines.Add("## Review Summary") | Out-Null
  $Lines.Add("") | Out-Null
  $CountsJson = ($ReviewState.counts | ConvertTo-Json -Compress)
  $Lines.Add("- counts: $CountsJson") | Out-Null
  $Lines.Add("") | Out-Null
}

Add-CommandSection -Lines $Lines -Title "think-refresh" -Output $RefreshOutput
Add-CommandSection -Lines $Lines -Title "think-health" -Output $HealthOutput
Add-CommandSection -Lines $Lines -Title "dream-lint" -Output $LintOutput
Add-CommandSection -Lines $Lines -Title "dream-review" -Output $ReviewOutput

$Lines | Set-Content -LiteralPath $ReportFile -Encoding UTF8
Write-Output "A-Brain dream-maintain report: $ReportFile"
