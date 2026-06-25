param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ReportDir = Join-Path $Root "dream/lint"
$JsonReportPath = Join-Path $ReportDir "lint-report.json"
$MarkdownReportPath = Join-Path $ReportDir "lint-report.md"

$AllowedStatuses = @("fresh", "validated", "promoted", "superseded", "archived")
$Issues = New-Object System.Collections.ArrayList

function New-Issue {
  param(
    [string]$Type,
    [string]$Severity,
    [string]$Path,
    [string]$Message,
    [string]$Target = $null
  )

  $Issue = [ordered]@{
    type = $Type
    severity = $Severity
    path = $Path
    message = $Message
  }
  if ($Target) {
    $Issue.target = $Target
  }
  return [pscustomobject]$Issue
}

function Get-RelativeRepoPath {
  param(
    [string]$BasePath,
    [string]$FullPath
  )

  $BaseUri = New-Object System.Uri(($BasePath.TrimEnd('\') + '\'))
  $FullUri = New-Object System.Uri($FullPath)
  $RelativeUri = $BaseUri.MakeRelativeUri($FullUri)
  return [System.Uri]::UnescapeDataString($RelativeUri.ToString()).Replace('/', '\')
}

function Resolve-RelativeTarget {
  param(
    [string]$SourceDirectory,
    [string]$TargetPath
  )

  $Combined = [System.IO.Path]::Combine($SourceDirectory, $TargetPath)
  try {
    return [System.IO.Path]::GetFullPath($Combined)
  } catch {
    return $null
  }
}

function Resolve-CitationTarget {
  param(
    [string]$RepoRoot,
    [string]$SourceDirectory,
    [string]$TargetPath
  )

  $Candidates = @(
    (Resolve-RelativeTarget -SourceDirectory $RepoRoot -TargetPath $TargetPath),
    (Resolve-RelativeTarget -SourceDirectory $SourceDirectory -TargetPath $TargetPath)
  )

  foreach ($Candidate in $Candidates) {
    if ($null -ne $Candidate -and (Test-Path -LiteralPath $Candidate)) {
      return $Candidate
    }
  }

  return $null
}

function Get-FrontmatterInfo {
  param(
    [string[]]$Lines
  )

  $Info = [ordered]@{
    hasFrontmatter = $false
    frontmatterLines = @()
    status = $null
    confidenceScore = $null
  }

  if ($Lines.Count -eq 0) {
    return [pscustomobject]$Info
  }

  if ($Lines[0].Trim() -ne "---") {
    return [pscustomobject]$Info
  }

  $ClosingIndex = -1
  for ($Index = 1; $Index -lt $Lines.Count; $Index++) {
    if ($Lines[$Index].Trim() -eq "---") {
      $ClosingIndex = $Index
      break
    }
  }

  if ($ClosingIndex -lt 1) {
    return [pscustomobject]$Info
  }

  $Info.hasFrontmatter = $true
  $Info.frontmatterLines = @($Lines[1..($ClosingIndex - 1)])

  foreach ($Line in $Info.frontmatterLines) {
    if ($null -eq $Info.status -and $Line -match '^\s*status\s*:\s*(.+?)\s*$') {
      $Info.status = $Matches[1].Trim().Trim("'`"")
      continue
    }
    if ($null -eq $Info.confidenceScore -and $Line -match '^\s*confidenceScore\s*:\s*(.+?)\s*$') {
      $Info.confidenceScore = $Matches[1].Trim().Trim("'`"")
    }
  }

  return [pscustomobject]$Info
}

function Add-Issue {
  param(
    [string]$Type,
    [string]$Severity,
    [string]$Path,
    [string]$Message,
    [string]$Target = $null
  )

  [void]$script:Issues.Add((New-Issue -Type $Type -Severity $Severity -Path $Path -Message $Message -Target $Target))
}

New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

$MarkdownFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter *.md -ErrorAction SilentlyContinue)
$SlugFiles = @()
$KnowledgeRoot = Join-Path $Root "knowledge"
$IngestCandidatesRoot = Join-Path $Root "ingest/candidates"
if (Test-Path -LiteralPath $KnowledgeRoot) {
  $SlugFiles += @(Get-ChildItem -LiteralPath $KnowledgeRoot -Recurse -File -Filter *.md -ErrorAction SilentlyContinue)
}
if (Test-Path -LiteralPath $IngestCandidatesRoot) {
  $SlugFiles += @(Get-ChildItem -LiteralPath $IngestCandidatesRoot -Recurse -File -Filter *.md -ErrorAction SilentlyContinue)
}

$SlugMap = @{}

foreach ($File in $MarkdownFiles) {
  $RelativePath = Get-RelativeRepoPath -BasePath $Root -FullPath $File.FullName
  $Content = Get-Content -LiteralPath $File.FullName -Raw
  $Lines = @()
  if ($Content.Length -gt 0) {
    $Lines = @($Content -split "`r?`n")
  }

  $Frontmatter = Get-FrontmatterInfo -Lines $Lines
  if ($Frontmatter.hasFrontmatter) {
    $HasKey = $false
    foreach ($Line in $Frontmatter.frontmatterLines) {
      if ($Line -match '^\s*[A-Za-z0-9_-]+\s*:') {
        $HasKey = $true
        break
      }
    }
    if (-not $HasKey) {
      Add-Issue -Type "empty_frontmatter" -Severity "warning" -Path $RelativePath -Message "Frontmatter exists but contains no key fields."
    }

    if ($null -ne $Frontmatter.status -and ($AllowedStatuses -notcontains $Frontmatter.status)) {
      Add-Issue -Type "invalid_status" -Severity "error" -Path $RelativePath -Message ("Invalid status '{0}'. Allowed: {1}" -f $Frontmatter.status, ($AllowedStatuses -join ", "))
    }

    if ($null -ne $Frontmatter.confidenceScore -and $Frontmatter.confidenceScore -notmatch '^(100|[0-9]{1,2})$') {
      Add-Issue -Type "invalid_confidence_score" -Severity "error" -Path $RelativePath -Message ("confidenceScore must be an integer from 0 to 100, got '{0}'." -f $Frontmatter.confidenceScore)
    }
  }

  $MarkdownLinkMatches = [regex]::Matches($Content, '(?ms)\[[^\]]+\]\(([^)]+)\)')
  foreach ($Match in $MarkdownLinkMatches) {
    $RawTarget = $Match.Groups[1].Value.Trim()
    if (-not $RawTarget) { continue }
    if (($RawTarget.StartsWith("<") -and $RawTarget.EndsWith(">"))) {
      $RawTarget = $RawTarget.Substring(1, $RawTarget.Length - 2).Trim()
    }
    if ($RawTarget -match '^(https?:|mailto:|#)') { continue }

    $LinkTarget = $RawTarget
    $AnchorIndex = $LinkTarget.IndexOf('#')
    if ($AnchorIndex -ge 0) {
      $LinkTarget = $LinkTarget.Substring(0, $AnchorIndex)
    }
    $QueryIndex = $LinkTarget.IndexOf('?')
    if ($QueryIndex -ge 0) {
      $LinkTarget = $LinkTarget.Substring(0, $QueryIndex)
    }
    $LinkTarget = $LinkTarget.Trim()

    if (-not $LinkTarget) { continue }
    if ([System.IO.Path]::IsPathRooted($LinkTarget)) { continue }
    if ([System.IO.Path]::GetExtension($LinkTarget).ToLowerInvariant() -ne ".md") { continue }

    $ResolvedLink = Resolve-RelativeTarget -SourceDirectory $File.DirectoryName -TargetPath $LinkTarget
    if ($null -eq $ResolvedLink -or -not (Test-Path -LiteralPath $ResolvedLink)) {
      Add-Issue -Type "broken_markdown_link" -Severity "error" -Path $RelativePath -Message ("Broken markdown link target '{0}'." -f $LinkTarget) -Target $LinkTarget
    }
  }

  $InFencedCodeBlock = $false
  $CurrentHeading = $null
  $ScanCitationInFence = $false
  foreach ($Line in $Lines) {
    if ($InFencedCodeBlock) {
      if ($Line -match '^\s*```') {
        $InFencedCodeBlock = $false
        $ScanCitationInFence = $false
      } elseif ($ScanCitationInFence -and $Line -match '^\s*path\s*:\s*(.+)$') {
        $CitationTarget = $Matches[1].Trim().Trim("'`"")
        if (-not [string]::IsNullOrWhiteSpace($CitationTarget) -and $CitationTarget -notmatch '^(https?:|mailto:|file:|[A-Za-z]:\\|\\\\)') {
          $ResolvedCitation = Resolve-CitationTarget -RepoRoot $Root -SourceDirectory $File.DirectoryName -TargetPath $CitationTarget
          if ($null -eq $ResolvedCitation) {
            Add-Issue -Type "broken_citation" -Severity "warning" -Path $RelativePath -Message ("Broken local citation path '{0}'." -f $CitationTarget) -Target $CitationTarget
          }
        }
      }
      continue
    }

    if ($Line -match '^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$') {
      $CurrentHeading = $Matches[1].Trim()
      continue
    }

    if ($Line -match '^\s*```([A-Za-z0-9_-]+)?\s*$') {
      $InFencedCodeBlock = $true
      $FenceLanguage = $Matches[1]
      $ScanCitationInFence = ($CurrentHeading -ieq "Claims" -and ($FenceLanguage -match '^(yaml|yml)$'))
      continue
    }

    if ($Line -notmatch '^\s*path\s*[:=]\s*') { continue }
    if ($Line -match '^\s*path\s*[:=]\s*(.+)$') {
      $CitationTarget = $Matches[1].Trim()
      $CitationTarget = $CitationTarget.Trim("'`"")
      if (-not $CitationTarget) { continue }
      if ($CitationTarget -match '^(https?:|mailto:|file:|[A-Za-z]:\\|\\\\)') { continue }

      $ResolvedCitation = Resolve-CitationTarget -RepoRoot $Root -SourceDirectory $File.DirectoryName -TargetPath $CitationTarget
      if ($null -eq $ResolvedCitation) {
        Add-Issue -Type "broken_citation" -Severity "warning" -Path $RelativePath -Message ("Broken local citation path '{0}'." -f $CitationTarget) -Target $CitationTarget
      }
    }
  }
}

foreach ($File in $SlugFiles) {
  $Slug = [System.IO.Path]::GetFileNameWithoutExtension($File.Name).ToLowerInvariant()
  $RelativePath = Get-RelativeRepoPath -BasePath $Root -FullPath $File.FullName
  if (-not $SlugMap.ContainsKey($Slug)) {
    $SlugMap[$Slug] = New-Object System.Collections.ArrayList
  }
  [void]$SlugMap[$Slug].Add($RelativePath)
}

foreach ($Slug in $SlugMap.Keys) {
  $Paths = @($SlugMap[$Slug])
  if ($Paths.Count -gt 1) {
    $JoinedPaths = $Paths -join ", "
    foreach ($RelativePath in $Paths) {
      Add-Issue -Type "duplicate_slug" -Severity "error" -Path $RelativePath -Message ("Duplicate slug '{0}' found in: {1}" -f $Slug, $JoinedPaths) -Target $Slug
    }
  }
}

$CountsByType = [ordered]@{}
foreach ($Issue in $Issues) {
  if (-not $CountsByType.Contains($Issue.type)) {
    $CountsByType[$Issue.type] = 0
  }
  $CountsByType[$Issue.type] += 1
}

$SortedIssues = @($Issues | Sort-Object path, type, target)
$Report = [ordered]@{
  schema = "a-brain-dream-lint-report-v1"
  generatedAt = (Get-Date).ToString("o")
  issueCount = $SortedIssues.Count
  countsByType = $CountsByType
  issues = $SortedIssues
}

$MarkdownLines = @(
  "# A-Brain Dream Lint Report",
  "",
  "- Generated: $($Report.generatedAt)",
  "- Issue count: $($Report.issueCount)",
  "- JSON: dream/lint/lint-report.json",
  ""
)

if ($CountsByType.Keys.Count -eq 0) {
  $MarkdownLines += "## Counts"
  $MarkdownLines += ""
  $MarkdownLines += "No issues."
} else {
  $MarkdownLines += "## Counts"
  $MarkdownLines += ""
  foreach ($Key in $CountsByType.Keys) {
    $MarkdownLines += "- ${Key}: $($CountsByType[$Key])"
  }
}

$MarkdownLines += ""
$MarkdownLines += "## Issues"
$MarkdownLines += ""

if ($SortedIssues.Count -eq 0) {
  $MarkdownLines += "No issues."
} else {
  foreach ($Issue in $SortedIssues) {
    $Line = "- [$($Issue.severity)] $($Issue.type) $($Issue.path): $($Issue.message)"
    if ($Issue.PSObject.Properties.Name -contains "target") {
      $Line += " Target: $($Issue.target)"
    }
    $MarkdownLines += $Line
  }
}

$Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $JsonReportPath -Encoding UTF8
$MarkdownLines | Set-Content -LiteralPath $MarkdownReportPath -Encoding UTF8

Write-Output "A-Brain dream-lint JSON report: $JsonReportPath"
Write-Output "A-Brain dream-lint Markdown report: $MarkdownReportPath"
Write-Output ("Issue count: {0}" -f $Report.issueCount)
