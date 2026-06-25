param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$ReportDir = Join-Path $Root "think/reports"
$ReportFile = Join-Path $ReportDir "health-report.json"
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

$RequiredDirs = @("diary", "library", "ingest", "knowledge", "think", "dream", "learn")
$ExcludedRelativeDirs = @(
  "think/indexes",
  "think/reports",
  "dream/reports",
  "dream/review/reports",
  "ingest/runs",
  "ingest/manifests",
  "diary/events",
  "diary/turns",
  "diary/sessions"
)
$KnowledgePageRelativeDirs = @(
  "knowledge/notes",
  "knowledge/projects",
  "knowledge/processes",
  "knowledge/concepts",
  "knowledge/skills"
)
$IndexSearchRelativeDirs = @("diary", "knowledge", "library")
$IndexSearchExtensions = @(".md", ".json", ".jsonl", ".txt")
$ReviewQueueFile = Join-Path $Root "dream/review/queue.json"
$EventFile = Join-Path $Root "diary/events/events.jsonl"
$TextIndexFile = Join-Path $Root "think/indexes/text-index.json"
$SyncStateFile = Join-Path $Root "think/indexes/sync-state.json"

function Get-RepoRelativePath {
  param([string]$Path)
  $Relative = $Path.Substring($Root.Length).TrimStart("\")
  return $Relative.Replace("\", "/")
}

function Test-IsExcludedPath {
  param([string]$Path)
  $Relative = Get-RepoRelativePath -Path $Path
  foreach ($Excluded in $ExcludedRelativeDirs) {
    if ($Relative -eq $Excluded -or $Relative.StartsWith("$Excluded/")) {
      return $true
    }
  }

  return $false
}

function Get-ScopedFiles {
  param(
    [string[]]$RelativeRoots,
    [string[]]$Extensions
  )

  $Files = foreach ($RelativeRoot in $RelativeRoots) {
    $AbsoluteRoot = Join-Path $Root $RelativeRoot
    if (-not (Test-Path -LiteralPath $AbsoluteRoot)) {
      continue
    }

    Get-ChildItem -LiteralPath $AbsoluteRoot -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object {
        (-not (Test-IsExcludedPath -Path $_.FullName)) -and
        ($null -eq $Extensions -or $Extensions.Count -eq 0 -or $Extensions -contains $_.Extension.ToLowerInvariant())
      }
  }

  return @($Files)
}

function Get-JsonFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-AgeMinutes {
  param($UpdatedAt)
  if ($null -eq $UpdatedAt) {
    return $null
  }

  try {
    $Parsed = [datetimeoffset]::Parse([string]$UpdatedAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
  } catch {
    return $null
  }

  return [math]::Round(((Get-Date).ToUniversalTime() - $Parsed.UtcDateTime).TotalMinutes, 2)
}

function Get-TextContent {
  param([string]$Path)
  try {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
  } catch {
    return Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
  }
}

function Get-JsonlObjects {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return @()
  }

  $Items = New-Object System.Collections.Generic.List[object]
  foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue) {
    if ([string]::IsNullOrWhiteSpace($Line)) {
      continue
    }

    try {
      $Items.Add(($Line | ConvertFrom-Json))
    } catch {
      # Ignore malformed lines so the health report still renders.
    }
  }

  return $Items.ToArray()
}

function Get-KnowledgePageStats {
  param([System.IO.FileInfo[]]$Files)

  $PagesWithSourceIds = 0
  $PagesWithSourceHashes = 0
  $PagesWithAnySourceMarker = 0
  $CitationCoverageCounts = [ordered]@{
    none = 0
    partial = 0
    good = 0
    full = 0
    missing = 0
    other = 0
  }
  $ClaimMentions = 0
  $CitationMentions = 0

  foreach ($File in $Files) {
    $Content = Get-TextContent -Path $File.FullName
    if ($null -eq $Content) {
      $Content = ""
    }

    $HasSourceIds = $Content -match '(?mi)^\s*sourceIds\s*:'
    $HasSourceHashes = $Content -match '(?mi)^\s*sourceHashes\s*:'
    if ($HasSourceIds) { $PagesWithSourceIds += 1 }
    if ($HasSourceHashes) { $PagesWithSourceHashes += 1 }
    if ($HasSourceIds -or $HasSourceHashes) { $PagesWithAnySourceMarker += 1 }

    $CoverageMatch = [regex]::Match($Content, '(?mi)^\s*citationCoverage\s*:\s*(none|partial|good|full)\s*$')
    if ($CoverageMatch.Success) {
      $CitationCoverageCounts[$CoverageMatch.Groups[1].Value.ToLowerInvariant()] += 1
    } elseif ($Content -match '(?mi)^\s*citationCoverage\s*:') {
      $CitationCoverageCounts.other += 1
    } else {
      $CitationCoverageCounts.missing += 1
    }

    $ClaimMentions += [regex]::Matches($Content, '(?i)\bclaim(s)?\b').Count
    $CitationMentions += [regex]::Matches($Content, '(?i)\bcitation(s)?\b').Count
  }

  return [ordered]@{
    totalKnowledgePages = @($Files).Count
    pagesWithSourceIds = $PagesWithSourceIds
    pagesWithSourceHashes = $PagesWithSourceHashes
    pagesWithAnySourceMarker = $PagesWithAnySourceMarker
    coverageRatio = if (@($Files).Count -gt 0) {
      [math]::Round($PagesWithAnySourceMarker / @($Files).Count, 4)
    } else {
      $null
    }
    citationCoverageCounts = $CitationCoverageCounts
    claimMentions = $ClaimMentions
    citationMentions = $CitationMentions
  }
}

$DirStatus = foreach ($Dir in $RequiredDirs) {
  [ordered]@{ path = $Dir; exists = (Test-Path -LiteralPath (Join-Path $Root $Dir)) }
}

$AllMarkdownFiles = @(Get-ScopedFiles -RelativeRoots @(".") -Extensions @(".md"))
$AllJsonFiles = @(Get-ScopedFiles -RelativeRoots @(".") -Extensions @(".json"))
$KnowledgePages = @(Get-ScopedFiles -RelativeRoots $KnowledgePageRelativeDirs -Extensions @(".md"))
$LibrarySourceFiles = @(Get-ScopedFiles -RelativeRoots @("library/sources") -Extensions $null | Where-Object { $_.Name -ne ".gitkeep" })
$KnowledgeNotes = @(Get-ScopedFiles -RelativeRoots @("knowledge/notes") -Extensions @(".md"))
$KnowledgeProjects = @(Get-ScopedFiles -RelativeRoots @("knowledge/projects") -Extensions @(".md"))
$KnowledgeProcesses = @(Get-ScopedFiles -RelativeRoots @("knowledge/processes") -Extensions @(".md"))
$KnowledgeConcepts = @(Get-ScopedFiles -RelativeRoots @("knowledge/concepts") -Extensions @(".md"))
$KnowledgeSkills = @(Get-ScopedFiles -RelativeRoots @("knowledge/skills") -Extensions @(".md"))
$IndexableFiles = @(Get-ScopedFiles -RelativeRoots $IndexSearchRelativeDirs -Extensions $IndexSearchExtensions)
$KnowledgeStats = Get-KnowledgePageStats -Files $KnowledgePages
$EventObjects = @(Get-JsonlObjects -Path $EventFile)

$Queue = Get-JsonFile -Path $ReviewQueueFile
$QueueItems = @()
if ($null -ne $Queue -and $null -ne $Queue.items) {
  $QueueItems = @($Queue.items)
}

$ReviewStateCounts = [ordered]@{}
foreach ($Item in $QueueItems) {
  $State = $null
  if ($null -ne $Item.human_review -and $null -ne $Item.human_review.state) {
    $State = [string]$Item.human_review.state
  }
  if ([string]::IsNullOrWhiteSpace($State)) {
    $State = "missing"
  }
  if (-not $ReviewStateCounts.Contains($State)) {
    $ReviewStateCounts[$State] = 0
  }
  $ReviewStateCounts[$State] += 1
}

$ThinkQueryCount = @($EventObjects | Where-Object { $_.type -eq "think_query" }).Count
$NoteWrittenCount = @($EventObjects | Where-Object { $_.type -eq "note_written" }).Count
$TextIndex = Get-JsonFile -Path $TextIndexFile
$SyncState = Get-JsonFile -Path $SyncStateFile
$TextIndexUpdatedAt = if ($null -ne $TextIndex) { $TextIndex.updatedAt } else { $null }
$SyncStateUpdatedAt = if ($null -ne $SyncState) { $SyncState.updatedAt } else { $null }
$TextIndexEntryCount = if ($null -ne $TextIndex -and $null -ne $TextIndex.entryCount) { [int]$TextIndex.entryCount } else { $null }
$SyncStateFileCount = if ($null -ne $SyncState -and $null -ne $SyncState.fileCount) { [int]$SyncState.fileCount } else { $null }
$ReviewPending = @($QueueItems | Where-Object { $_.human_review.state -eq "pending_human_review" }).Count

$Report = [ordered]@{
  schema = "a-brain-think-health-v2"
  generatedAt = (Get-Date).ToString("o")
  directories = @($DirStatus)
  counts = [ordered]@{
    markdownFiles = @($AllMarkdownFiles).Count
    jsonFiles = @($AllJsonFiles).Count
    diaryEvents = @($EventObjects).Count
    reviewBacklog = @($QueueItems).Count
  }
  index = [ordered]@{
    syncStateExists = (Test-Path -LiteralPath $SyncStateFile)
    textIndexExists = (Test-Path -LiteralPath $TextIndexFile)
    syncStateUpdatedAt = $SyncStateUpdatedAt
    textIndexUpdatedAt = $TextIndexUpdatedAt
    syncStateFileCount = $SyncStateFileCount
    textIndexEntryCount = $TextIndexEntryCount
  }
  sourceCoverage = [ordered]@{
    librarySourceCount = @($LibrarySourceFiles).Count
    knowledgeCounts = [ordered]@{
      notes = @($KnowledgeNotes).Count
      projects = @($KnowledgeProjects).Count
      processes = @($KnowledgeProcesses).Count
      concepts = @($KnowledgeConcepts).Count
      skills = @($KnowledgeSkills).Count
    }
    sourceMarkerStats = [ordered]@{
      totalKnowledgePages = $KnowledgeStats.totalKnowledgePages
      pagesWithSourceIds = $KnowledgeStats.pagesWithSourceIds
      pagesWithSourceHashes = $KnowledgeStats.pagesWithSourceHashes
      pagesWithAnySourceMarker = $KnowledgeStats.pagesWithAnySourceMarker
      coverageRatio = $KnowledgeStats.coverageRatio
    }
  }
  indexFreshness = [ordered]@{
    textIndex = [ordered]@{
      exists = (Test-Path -LiteralPath $TextIndexFile)
      updatedAt = $TextIndexUpdatedAt
      ageMinutes = Get-AgeMinutes -UpdatedAt $TextIndexUpdatedAt
      entryCount = $TextIndexEntryCount
    }
    syncState = [ordered]@{
      exists = (Test-Path -LiteralPath $SyncStateFile)
      updatedAt = $SyncStateUpdatedAt
      ageMinutes = Get-AgeMinutes -UpdatedAt $SyncStateUpdatedAt
      fileCount = $SyncStateFileCount
    }
    indexableFileCount = @($IndexableFiles).Count
  }
  citationCoverage = [ordered]@{
    totalKnowledgePages = $KnowledgeStats.totalKnowledgePages
    citationCoverageCounts = $KnowledgeStats.citationCoverageCounts
    claimMentions = $KnowledgeStats.claimMentions
    citationMentions = $KnowledgeStats.citationMentions
  }
  reviewBacklog = [ordered]@{
    total = @($QueueItems).Count
    pending_human_review = $ReviewPending
    byHumanReviewState = $ReviewStateCounts
  }
  querySaveRate = [ordered]@{
    eventFileExists = (Test-Path -LiteralPath $EventFile)
    think_query = $ThinkQueryCount
    note_written = $NoteWrittenCount
    ratio = if ($ThinkQueryCount -gt 0) {
      [math]::Round($NoteWrittenCount / $ThinkQueryCount, 4)
    } else {
      $null
    }
  }
  warnings = @()
}

if (-not $Report.index.textIndexExists) {
  $Report.warnings += "text_index_missing_run_think_refresh"
}
if (-not $Report.index.syncStateExists) {
  $Report.warnings += "sync_state_missing_run_think_refresh"
}
if ($Report.reviewBacklog.pending_human_review -gt 0) {
  $Report.warnings += "review_backlog_non_empty"
}
if ($null -ne $TextIndexEntryCount -and $TextIndexEntryCount -lt $Report.indexFreshness.indexableFileCount) {
  $Report.warnings += "text_index_entry_count_below_indexable_files"
}
if ($null -eq $Report.sourceCoverage.sourceMarkerStats.coverageRatio) {
  $Report.warnings += "source_coverage_no_knowledge_pages"
}

$Report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ReportFile -Encoding UTF8

Write-Output "A-Brain think-health report: $ReportFile"
Write-Output ("Counts: Markdown={0}; JSON={1}; diaryEvents={2}; reviewBacklog={3}" -f $Report.counts.markdownFiles, $Report.counts.jsonFiles, $Report.counts.diaryEvents, $Report.counts.reviewBacklog)
Write-Output ("sourceCoverage: librarySources={0}; knowledgePages={1}; coverageRatio={2}" -f $Report.sourceCoverage.librarySourceCount, $Report.sourceCoverage.sourceMarkerStats.totalKnowledgePages, $Report.sourceCoverage.sourceMarkerStats.coverageRatio)
Write-Output ("indexFreshness: textIndexExists={0}; syncStateExists={1}; indexableFiles={2}; textIndexAgeMinutes={3}; syncStateAgeMinutes={4}" -f $Report.indexFreshness.textIndex.exists, $Report.indexFreshness.syncState.exists, $Report.indexFreshness.indexableFileCount, $Report.indexFreshness.textIndex.ageMinutes, $Report.indexFreshness.syncState.ageMinutes)
Write-Output ("citationCoverage: none={0}; partial={1}; good={2}; full={3}; missing={4}" -f $Report.citationCoverage.citationCoverageCounts.none, $Report.citationCoverage.citationCoverageCounts.partial, $Report.citationCoverage.citationCoverageCounts.good, $Report.citationCoverage.citationCoverageCounts.full, $Report.citationCoverage.citationCoverageCounts.missing)
Write-Output ("reviewBacklog: total={0}; pending_human_review={1}" -f $Report.reviewBacklog.total, $Report.reviewBacklog.pending_human_review)
Write-Output ("querySaveRate: think_query={0}; note_written={1}; ratio={2}" -f $Report.querySaveRate.think_query, $Report.querySaveRate.note_written, $Report.querySaveRate.ratio)
if ($Report.warnings.Count -gt 0) {
  Write-Output ("Warnings: " + ($Report.warnings -join ", "))
}
