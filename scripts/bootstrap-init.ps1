param(
  [string]$ProjectTitle = "",
  [string]$ProjectPath = "",
  [string]$ProjectSummary = "",
  [switch]$UseExamples,
  [switch]$RunMaintain
)

$ErrorActionPreference = "Stop"

function Get-Slug {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  $Slug = $Value.ToLowerInvariant()
  $Slug = [regex]::Replace($Slug, '[^a-z0-9]+', '-')
  $Slug = $Slug.Trim('-')
  if ([string]::IsNullOrWhiteSpace($Slug)) {
    return "project"
  }
  return $Slug
}

function New-RepoRelativePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BasePath,

    [Parameter(Mandatory = $true)]
    [string]$ChildPath
  )

  $BaseFull = [System.IO.Path]::GetFullPath($BasePath)
  $ChildFull = [System.IO.Path]::GetFullPath($ChildPath)
  $BaseUri = New-Object System.Uri(($BaseFull.TrimEnd('\') + '\'))
  $ChildUri = New-Object System.Uri($ChildFull)
  return [System.Uri]::UnescapeDataString($BaseUri.MakeRelativeUri($ChildUri).ToString()).Replace('/', '\')
}

function Ensure-SeedProject {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [string]$PathValue,

    [string]$SummaryValue = ""
  )

  $ProjectsDir = Join-Path $RepoRoot "knowledge/projects"
  New-Item -ItemType Directory -Force -Path $ProjectsDir | Out-Null

  $Slug = Get-Slug -Value $Title
  $TargetPath = Join-Path $ProjectsDir ($Slug + ".md")
  if (Test-Path -LiteralPath $TargetPath) {
    return [pscustomobject]@{
      created = $false
      path = $TargetPath
    }
  }

  $RelativePath = New-RepoRelativePath -BasePath $RepoRoot -ChildPath $PathValue
  if ([string]::IsNullOrWhiteSpace($SummaryValue)) {
    $SummaryValue = ("Initial project record created during bootstrap: {0}" -f $Title)
  }

  $Updated = (Get-Date).ToString("yyyy-MM-dd")
  $Content = @(
    "---",
    "title: $Title",
    "type: project",
    "tags: [bootstrap]",
    "source: local",
    "updated: $Updated",
    "summary: $SummaryValue",
    "status: fresh",
    "confidenceScore: 60",
    "confidenceFormulaVersion: a-brain-confidence-v1",
    "confidenceAggregation: p25",
    "claimSetPath:",
    "confidenceClaimRefs: []",
    "provenanceState: imported",
    "inferenceState: direct",
    "citationCoverage: none",
    "reviewState: draft",
    "schemaState: compliant",
    "sourceIds: []",
    "contradictedBy: []",
    "supersedes: []",
    "promoted_to:",
    "reviewQueueRefs: []",
    "modelId:",
    "promptVersion:",
    "contentHash:",
    "sourceHashes: []",
    "---",
    "",
    "# $Title",
    "",
    "## Path",
    "",
    $PathValue,
    "",
    "## Current State",
    "",
    "First project record created during bootstrap.",
    "",
    "## Important Files",
    "",
    "- $RelativePath",
    "",
    "## Next Actions",
    "",
    "- Add README, AGENTS, docs, or current priorities for this project."
  ) -join [Environment]::NewLine

  Set-Content -LiteralPath $TargetPath -Value $Content -Encoding UTF8
  return [pscustomobject]@{
    created = $true
    path = $TargetPath
  }
}

$Root = Split-Path -Parent $PSScriptRoot
$DiaryEventScript = Join-Path $PSScriptRoot "diary-event.ps1"
$DiaryDeriveScript = Join-Path $PSScriptRoot "diary-derive.ps1"
$ThinkRefreshScript = Join-Path $PSScriptRoot "think-refresh.ps1"
$ThinkHealthScript = Join-Path $PSScriptRoot "think-health.ps1"
$DreamMaintainScript = Join-Path $PSScriptRoot "dream-maintain.ps1"
$IngestScript = Join-Path $PSScriptRoot "ingest-library.ps1"
$ExamplesDir = Join-Path $Root "examples"

$CreatedPaths = @()

$Summary = "Bootstrap A-Brain"
if (-not [string]::IsNullOrWhiteSpace($ProjectTitle)) {
  $Summary = "Bootstrap A-Brain for $ProjectTitle"
}

$Payload = @{
  action = "bootstrap_init"
  useExamples = [bool]$UseExamples
  projectTitle = $ProjectTitle
  projectPath = $ProjectPath
}
$PayloadJson = ($Payload | ConvertTo-Json -Compress)

Push-Location $Root
try {
  & $DiaryEventScript -Type task_start -Summary $Summary -PayloadJson $PayloadJson | Out-Null
  & $DiaryDeriveScript | Out-Null

  if (-not [string]::IsNullOrWhiteSpace($ProjectTitle) -and -not [string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectResult = Ensure-SeedProject -RepoRoot $Root -Title $ProjectTitle -PathValue $ProjectPath -SummaryValue $ProjectSummary
    if ($ProjectResult.created) {
      $CreatedPaths += (New-RepoRelativePath -BasePath $Root -ChildPath $ProjectResult.path)
    }
  }

  $SampleSourcePath = Join-Path $Root "library/sources/sample-source.md"
  $SampleNotePath = Join-Path $Root "knowledge/notes/sample-note.md"
  if ($UseExamples) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $SampleSourcePath), (Split-Path -Parent $SampleNotePath) | Out-Null

    if (-not (Test-Path -LiteralPath $SampleSourcePath)) {
      Copy-Item -LiteralPath (Join-Path $ExamplesDir "sample-source.md") -Destination $SampleSourcePath
      $CreatedPaths += (New-RepoRelativePath -BasePath $Root -ChildPath $SampleSourcePath)
    }

    if (-not (Test-Path -LiteralPath $SampleNotePath)) {
      Copy-Item -LiteralPath (Join-Path $ExamplesDir "sample-note.md") -Destination $SampleNotePath
      $CreatedPaths += (New-RepoRelativePath -BasePath $Root -ChildPath $SampleNotePath)
    }

    & $IngestScript -SourcePath $SampleSourcePath | Out-Null
  }

  & $ThinkRefreshScript | Out-Null
  & $ThinkHealthScript | Out-Null

  if ($RunMaintain -or $UseExamples) {
    & $DreamMaintainScript | Out-Null
  }
} finally {
  Pop-Location
}

Write-Output "A-Brain bootstrap-init complete."
Write-Output ("repo root: {0}" -f $Root)
if ($CreatedPaths.Count -gt 0) {
  Write-Output "created:"
  $CreatedPaths | ForEach-Object { Write-Output ("- " + $_) }
} else {
  Write-Output "created: none"
}

if ($UseExamples) {
  Write-Output "examples: imported sample source and sample note"
}

if (-not [string]::IsNullOrWhiteSpace($ProjectTitle) -and -not [string]::IsNullOrWhiteSpace($ProjectPath)) {
  Write-Output ("project: {0} [{1}]" -f $ProjectTitle, $ProjectPath)
}

Write-Output "next:"
Write-Output "- merge AGENTS.example.md into your workspace rules"
Write-Output "- add more project pages and library sources as needed"
Write-Output "- run dream-review.cmd -Report when you want to inspect queued review items"
