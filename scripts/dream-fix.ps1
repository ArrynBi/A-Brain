param(
  [string]$ReportPath = "dream/lint/lint-report.json",
  [string]$OutDir = "dream/correction"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
  param(
    [string]$BasePath,
    [string]$InputPath
  )

  if ([string]::IsNullOrWhiteSpace($InputPath)) {
    return $null
  }

  if ([System.IO.Path]::IsPathRooted($InputPath)) {
    return [System.IO.Path]::GetFullPath($InputPath)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $InputPath))
}

function Get-UniqueFilePath {
  param(
    [string]$Directory,
    [string]$Prefix,
    [string]$Extension
  )

  $Timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss-fff")
  $Candidate = Join-Path $Directory ("{0}-{1}.{2}" -f $Prefix, $Timestamp, $Extension)
  if (-not (Test-Path -LiteralPath $Candidate)) {
    return $Candidate
  }

  $Suffix = 2
  while ($true) {
    $WithSuffix = Join-Path $Directory ("{0}-{1}-{2}.{3}" -f $Prefix, $Timestamp, $Suffix, $Extension)
    if (-not (Test-Path -LiteralPath $WithSuffix)) {
      return $WithSuffix
    }
    $Suffix += 1
  }
}

function Test-PathWithin {
  param(
    [string]$ParentPath,
    [string]$ChildPath
  )

  $ResolvedParent = [System.IO.Path]::GetFullPath($ParentPath).TrimEnd('\')
  $ResolvedChild = [System.IO.Path]::GetFullPath($ChildPath).TrimEnd('\')

  return $ResolvedChild.Equals($ResolvedParent, [System.StringComparison]::OrdinalIgnoreCase) -or
    $ResolvedChild.StartsWith($ResolvedParent + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-SuggestedAction {
  param([string]$IssueType)

  switch ($IssueType) {
    "broken_markdown_link" { return "verify or update/remove link target" }
    "empty_frontmatter" { return "add required frontmatter keys" }
    "duplicate_slug" { return "rename one document or add distinguishing slug" }
    "invalid_status" { return "replace with allowed status" }
    "invalid_confidence_score" { return "set integer 0-100" }
    "broken_citation" { return "verify citation target or remove citation" }
    default { return "review issue and decide manual correction" }
  }
}

function New-PreviewItem {
  param($Issue)

  $IssueType = [string]$Issue.type
  $Target = $null
  if ($Issue.PSObject.Properties.Name -contains "target") {
    $Target = [string]$Issue.target
  }

  $Reason = [string]$Issue.message
  if ([string]::IsNullOrWhiteSpace($Reason)) {
    $Reason = "Reported by dream-lint; human review required before source edits."
  }

  return [pscustomobject][ordered]@{
    issueType = $IssueType
    severity = [string]$Issue.severity
    path = [string]$Issue.path
    target = $Target
    suggestedAction = Get-SuggestedAction -IssueType $IssueType
    applyable = $false
    reason = $Reason
  }
}

$ResolvedReportPath = Resolve-RepoPath -BasePath $Root -InputPath $ReportPath
$ResolvedOutDir = Resolve-RepoPath -BasePath $Root -InputPath $OutDir
$AllowedOutRoot = Join-Path $Root "dream/correction"

if (-not (Test-PathWithin -ParentPath $AllowedOutRoot -ChildPath $ResolvedOutDir)) {
  throw ("dream-fix: OutDir must stay within {0}. Got: {1}" -f $AllowedOutRoot, $ResolvedOutDir)
}

if (-not (Test-Path -LiteralPath $ResolvedReportPath)) {
  Write-Output ("dream-fix: lint report not found at {0}" -f $ResolvedReportPath)
  Write-Output "dream-fix: run .\scripts\dream-lint.cmd first."
  exit 0
}

$LintReport = Get-Content -LiteralPath $ResolvedReportPath -Raw | ConvertFrom-Json
$LintIssues = @()
if ($null -ne $LintReport -and $null -ne $LintReport.issues) {
  $LintIssues = @($LintReport.issues)
}

New-Item -ItemType Directory -Force -Path $ResolvedOutDir | Out-Null

$PreviewItems = @()
foreach ($Issue in $LintIssues) {
  $PreviewItems += New-PreviewItem -Issue $Issue
}

$JsonPath = Get-UniqueFilePath -Directory $ResolvedOutDir -Prefix "dream-fix-preview" -Extension "json"
$MarkdownPath = [System.IO.Path]::ChangeExtension($JsonPath, ".md")

$GeneratedAt = (Get-Date).ToString("o")
$PreviewReport = [pscustomobject][ordered]@{
  schema = "a-brain-dream-fix-preview-v1"
  generatedAt = $GeneratedAt
  sourceReportPath = $ResolvedReportPath
  previewCount = $PreviewItems.Count
  previewItems = @($PreviewItems)
}

$MarkdownLines = @(
  "# A-Brain Dream Fix Preview",
  "",
  "- Generated: $GeneratedAt",
  "- Mode: preview-only",
  "- Source lint report: $ResolvedReportPath",
  "- Preview count: $($PreviewItems.Count)",
  "- Writes source documents: false",
  ""
)

if ($PreviewItems.Count -eq 0) {
  $MarkdownLines += "## Preview Items"
  $MarkdownLines += ""
  $MarkdownLines += "No lint issues found in the input report."
} else {
  $MarkdownLines += "## Preview Items"
  $MarkdownLines += ""
  foreach ($Item in $PreviewItems) {
    $MarkdownLines += "### $($Item.issueType) :: $($Item.path)"
    $MarkdownLines += ""
    $MarkdownLines += "- severity: $($Item.severity)"
    $MarkdownLines += "- target: $($Item.target)"
    $MarkdownLines += "- suggestedAction: $($Item.suggestedAction)"
    $MarkdownLines += "- applyable: false"
    $MarkdownLines += "- reason: $($Item.reason)"
    $MarkdownLines += ""
  }
}

$PreviewReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $JsonPath -Encoding UTF8
$MarkdownLines | Set-Content -LiteralPath $MarkdownPath -Encoding UTF8

Write-Output "A-Brain dream-fix JSON preview: $JsonPath"
Write-Output "A-Brain dream-fix Markdown preview: $MarkdownPath"
Write-Output ("Preview count: {0}" -f $PreviewReport.previewCount)
Write-Output "Apply: false"
