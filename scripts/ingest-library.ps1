param(
  [string]$SourcePath = "library/sources",
  [int]$Limit = 20,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ($Limit -lt 1) {
  throw "-Limit must be greater than 0."
}

$Root = Split-Path -Parent $PSScriptRoot
$Now = Get-Date
$UpdatedDate = $Now.ToString("yyyy-MM-dd")
$IngestedAt = $Now.ToString("o")
$AllowedReviewStates = @(
  "draft",
  "pending_auto_review",
  "pending_human_review",
  "needs_source",
  "needs_revision",
  "accepted",
  "promoted",
  "rejected",
  "stale",
  "disputed",
  "superseded"
)

function Resolve-InputPath {
  param(
    [string]$InputPath,
    [string]$RootPath
  )

  if ([string]::IsNullOrWhiteSpace($InputPath)) {
    throw "SourcePath cannot be empty."
  }

  if ([System.IO.Path]::IsPathRooted($InputPath)) {
    return [System.IO.Path]::GetFullPath($InputPath)
  }

  $Candidates = @(
    $InputPath,
    (Join-Path (Get-Location).Path $InputPath),
    (Join-Path $RootPath $InputPath)
  )

  foreach ($Candidate in $Candidates) {
    if (Test-Path -LiteralPath $Candidate) {
      return [System.IO.Path]::GetFullPath($Candidate)
    }
  }

  return [System.IO.Path]::GetFullPath((Join-Path $RootPath $InputPath))
}

function Get-RepoRelativePath {
  param(
    [string]$RootPath,
    [string]$FullPath
  )

  $RootUri = New-Object System.Uri(($RootPath.TrimEnd('\') + '\'))
  $FileUri = New-Object System.Uri($FullPath)
  $Relative = $RootUri.MakeRelativeUri($FileUri).ToString()
  return [System.Uri]::UnescapeDataString($Relative).Replace('\', '/')
}

function Get-SafeSlug {
  param(
    [string]$Value,
    [string]$FallbackHash
  )

  $Slug = ""
  if (-not [string]::IsNullOrWhiteSpace($Value)) {
    $Slug = $Value.ToLowerInvariant()
    $Slug = [System.Text.RegularExpressions.Regex]::Replace($Slug, "[^a-z0-9]+", "-")
    $Slug = $Slug.Trim('-')
  }

  if ([string]::IsNullOrWhiteSpace($Slug)) {
    if ([string]::IsNullOrWhiteSpace($FallbackHash)) {
      $Slug = "item"
    } else {
      $Slug = $FallbackHash.Substring(0, [Math]::Min(8, $FallbackHash.Length)).ToLowerInvariant()
    }
  }

  return $Slug
}

function Get-Sha256Hex {
  param([byte[]]$Bytes)

  $Hasher = [System.Security.Cryptography.SHA256]::Create()
  try {
    $HashBytes = $Hasher.ComputeHash($Bytes)
    return ([System.BitConverter]::ToString($HashBytes)).Replace("-", "").ToLowerInvariant()
  } finally {
    $Hasher.Dispose()
  }
}

function Get-Sha256HexFromString {
  param([string]$Value)

  if ($null -eq $Value) {
    $Value = ""
  }

  $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  return Get-Sha256Hex -Bytes $Bytes
}

function Get-StablePathHash {
  param(
    [string]$RelativePath,
    [int]$Length = 10
  )

  $Hash = Get-Sha256HexFromString -Value $RelativePath
  return $Hash.Substring(0, [Math]::Min($Length, $Hash.Length)).ToLowerInvariant()
}

function Get-UniqueStringValue {
  param(
    [string]$BaseValue,
    [hashtable]$UsedValues
  )

  if (-not $UsedValues.ContainsKey($BaseValue)) {
    $UsedValues[$BaseValue] = 1
    return $BaseValue
  }

  $Attempt = [int]$UsedValues[$BaseValue] + 1
  while ($true) {
    $Candidate = "{0}-{1}" -f $BaseValue, $Attempt
    if (-not $UsedValues.ContainsKey($Candidate)) {
      $UsedValues[$BaseValue] = $Attempt
      $UsedValues[$Candidate] = 1
      return $Candidate
    }
    $Attempt += 1
  }
}

function Get-UniquePathValue {
  param(
    [string]$BasePath,
    [hashtable]$UsedPaths
  )

  if (-not $UsedPaths.ContainsKey($BasePath)) {
    $UsedPaths[$BasePath] = 1
    return $BasePath
  }

  $Extension = [System.IO.Path]::GetExtension($BasePath)
  $Directory = [System.IO.Path]::GetDirectoryName($BasePath)
  $Leaf = [System.IO.Path]::GetFileNameWithoutExtension($BasePath)
  $Attempt = [int]$UsedPaths[$BasePath] + 1

  while ($true) {
    $CandidateLeaf = "{0}-{1}" -f $Leaf, $Attempt
    $CandidateName = "{0}{1}" -f $CandidateLeaf, $Extension
    $CandidatePath = if ([string]::IsNullOrWhiteSpace($Directory)) {
      $CandidateName
    } else {
      ($Directory.Replace('\', '/') + "/" + $CandidateName)
    }

    if (-not $UsedPaths.ContainsKey($CandidatePath)) {
      $UsedPaths[$BasePath] = $Attempt
      $UsedPaths[$CandidatePath] = 1
      return $CandidatePath
    }
    $Attempt += 1
  }
}

function Read-TextWithUtf8Fallback {
  param([string]$Path)

  $Bytes = [System.IO.File]::ReadAllBytes($Path)
  $Utf8 = New-Object System.Text.UTF8Encoding($false, $true)
  try {
    $Text = $Utf8.GetString($Bytes)
    $EncodingUsed = "utf8"
  } catch {
    $Text = [System.Text.Encoding]::Default.GetString($Bytes)
    $EncodingUsed = "default"
  }

  return [pscustomobject]@{
    bytes = $Bytes
    text = $Text
    encoding = $EncodingUsed
  }
}

function Parse-SimpleFrontmatter {
  param([string]$Text)

  $Result = [ordered]@{
    fields = @{}
    body = $Text
    raw = $null
  }

  if ($Text -notmatch "^(---\r?\n)([\s\S]*?)\r?\n---\r?\n?") {
    return [pscustomobject]$Result
  }

  $FrontmatterBlock = $Matches[2]
  $BodyStart = $Matches[0].Length
  $BodyText = $Text.Substring($BodyStart)
  $Fields = @{}

  foreach ($Line in ($FrontmatterBlock -split "\r?\n")) {
    if ($Line -match "^\s*([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*$") {
      $Key = $Matches[1]
      $Value = $Matches[2].Trim()
      if (($Value.StartsWith("'") -and $Value.EndsWith("'")) -or ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        $Value = $Value.Substring(1, $Value.Length - 2)
      }
      $Fields[$Key] = $Value
    }
  }

  $Result.fields = $Fields
  $Result.body = $BodyText
  $Result.raw = $FrontmatterBlock
  return [pscustomobject]$Result
}

function Get-FirstParagraph {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return ""
  }

  $Normalized = $Text -replace "\r", ""
  $Paragraphs = $Normalized -split "\n\s*\n"
  foreach ($Paragraph in $Paragraphs) {
    $Clean = ($Paragraph -replace "\s+", " ").Trim()
    $Clean = $Clean.Trim('#').Trim()
    if (-not [string]::IsNullOrWhiteSpace($Clean)) {
      return $Clean
    }
  }

  return ""
}

function Get-SourceType {
  param(
    [string]$Extension,
    [string]$FrontmatterValue
  )

  if (-not [string]::IsNullOrWhiteSpace($FrontmatterValue)) {
    return $FrontmatterValue
  }

  switch ($Extension.ToLowerInvariant()) {
    ".md" { return "markdown" }
    ".txt" { return "manual" }
    default { return "manual" }
  }
}

function Format-YamlString {
  param([string]$Value)

  if ($null -eq $Value) {
    return "''"
  }

  return "'" + ($Value -replace "'", "''") + "'"
}

function Format-YamlInlineArray {
  param([object[]]$Values)

  if ($null -eq $Values -or $Values.Count -eq 0) {
    return "[]"
  }

  $Quoted = foreach ($Value in $Values) {
    Format-YamlString -Value ([string]$Value)
  }

  return "[ " + ($Quoted -join ", ") + " ]"
}

function New-ClaimsYamlBlock {
  param(
    [string]$SourceId,
    [string]$SourcePathValue,
    [string[]]$ClaimTexts,
    [int]$ConfidenceScore,
    [string]$ClaimPrefix
  )

  $Lines = @("claims:")
  $Index = 1

  foreach ($ClaimText in $ClaimTexts) {
    if ([string]::IsNullOrWhiteSpace($ClaimText)) {
      continue
    }

    $ClaimId = "{0}-{1:d3}" -f $ClaimPrefix, $Index
    $Lines += "  - id: $(Format-YamlString -Value $ClaimId)"
    $Lines += "    text: $(Format-YamlString -Value $ClaimText)"
    $Lines += "    claimType: " + $(if ($Index -eq 1) { "source_title" } else { "source_summary" })
    $Lines += "    confidenceScore: $ConfidenceScore"
    $Lines += "    confidenceFormulaVersion: a-brain-confidence-v1"
    $Lines += "    provenanceState: extracted"
    $Lines += "    inferenceState: direct"
    $Lines += "    reviewState: pending_human_review"
    $Lines += "    citations:"
    $Lines += "      - sourceId: $(Format-YamlString -Value $SourceId)"
    $Lines += "        path: $(Format-YamlString -Value $SourcePathValue)"
    $Index += 1
  }

  return ($Lines -join "`r`n")
}

function New-NoteCandidateContent {
  param(
    [string]$Title,
    [string]$Summary,
    [string]$Updated,
    [string]$SourceId,
    [string]$SourceHash,
    [string]$ReviewId,
    [string]$SourcePathValue,
    [string]$SourceType,
    [string]$LastWriteTimeUtc,
    [string]$ClaimsYaml,
    [string]$ContentHash
  )

  $Tags = Format-YamlInlineArray -Values @("ingest", "library", "candidate")
  $SourceIds = Format-YamlInlineArray -Values @($SourceId)
  $ReviewRefs = Format-YamlInlineArray -Values @($ReviewId)
  $SourceHashes = Format-YamlInlineArray -Values @($SourceHash)
  $QuotedTitle = Format-YamlString -Value $Title
  $QuotedSummary = Format-YamlString -Value $Summary
  $QuotedContentHash = Format-YamlString -Value $ContentHash
  $Code = [char]96

  $NoteContent = @"
---
title: $QuotedTitle
type: note
tags: $Tags
source: local
updated: $Updated
summary: $QuotedSummary
status: fresh
confidenceScore: 45
confidenceFormulaVersion: a-brain-confidence-v1
confidenceAggregation: p25
claimSetPath:
confidenceClaimRefs: []
provenanceState: extracted
inferenceState: direct
citationCoverage: partial
reviewState: pending_human_review
schemaState: compliant
sourceIds: $SourceIds
contradictedBy: []
supersedes: []
promoted_to:
reviewQueueRefs: $ReviewRefs
modelId:
promptVersion:
contentHash: $QuotedContentHash
sourceHashes: $SourceHashes
---

# $Title

## Summary

$Summary

## Details

- Source path: $Code$SourcePathValue$Code
- Source type: $Code$SourceType$Code
- Last write (UTC): $Code$LastWriteTimeUtc$Code
- Content hash: $Code$SourceHash$Code

## Claims

${Code}${Code}${Code}yaml
$ClaimsYaml
${Code}${Code}${Code}
"@
  return $NoteContent
}

function New-ConceptCandidateContent {
  param(
    [string]$Title,
    [string]$Summary,
    [string]$Updated,
    [string]$SourceId,
    [string]$SourceHash,
    [string]$ReviewId,
    [string]$SourcePathValue,
    [string]$ClaimsYaml,
    [string]$ContentHash
  )

  $Tags = Format-YamlInlineArray -Values @("ingest", "concept-candidate", "source-driven")
  $SourceIds = Format-YamlInlineArray -Values @($SourceId)
  $ReviewRefs = Format-YamlInlineArray -Values @($ReviewId)
  $SourceHashes = Format-YamlInlineArray -Values @($SourceHash)
  $QuotedTitle = Format-YamlString -Value $Title
  $QuotedSummary = Format-YamlString -Value $Summary
  $QuotedContentHash = Format-YamlString -Value $ContentHash
  $Code = [char]96

  $ConceptContent = @"
---
title: $QuotedTitle
type: concept
tags: $Tags
source: local
updated: $Updated
summary: $QuotedSummary
status: fresh
confidenceScore: 40
confidenceFormulaVersion: a-brain-confidence-v1
confidenceAggregation: p25
claimSetPath:
confidenceClaimRefs: []
provenanceState: extracted
inferenceState: direct
citationCoverage: partial
reviewState: pending_human_review
schemaState: compliant
sourceIds: $SourceIds
contradictedBy: []
supersedes: []
promoted_to:
reviewQueueRefs: $ReviewRefs
modelId:
promptVersion:
contentHash: $QuotedContentHash
sourceHashes: $SourceHashes
---

# $Title

## Summary

$Summary

## Details

- This is a source-driven concept candidate generated from $Code$SourceId$Code.
- Candidate source path: $Code$SourcePathValue$Code
- Promotion target is intentionally not ${Code}knowledge/concepts$Code.

## Claims

${Code}${Code}${Code}yaml
$ClaimsYaml
${Code}${Code}${Code}
"@
  return $ConceptContent
}

function Ensure-ParentDirectory {
  param([string]$Path)

  $Parent = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($Parent) -and -not (Test-Path -LiteralPath $Parent)) {
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null
  }
}

function Get-UniqueRunToken {
  param(
    [datetime]$BaseTime,
    [string]$ManifestDirectory,
    [string]$RunDirectory
  )

  $BaseToken = $BaseTime.ToString("yyyyMMdd-HHmmss-fff")
  $Attempt = 0

  while ($true) {
    $CandidateToken = if ($Attempt -eq 0) {
      $BaseToken
    } else {
      "{0}-{1:d2}" -f $BaseToken, $Attempt
    }

    $ManifestCandidate = Join-Path $ManifestDirectory ("library-manifest-{0}.json" -f $CandidateToken)
    $RunCandidate = Join-Path $RunDirectory ("ingest-library-run-{0}.json" -f $CandidateToken)
    if (-not (Test-Path -LiteralPath $ManifestCandidate) -and -not (Test-Path -LiteralPath $RunCandidate)) {
      return $CandidateToken
    }

    $Attempt += 1
  }
}

function Get-LatestManifestLookup {
  param([string]$ManifestDirectory)

  $Lookup = @{
    bySourceId = @{}
    bySourcePath = @{}
    manifestPath = ""
  }

  if (-not (Test-Path -LiteralPath $ManifestDirectory)) {
    return $Lookup
  }

  $LatestManifest = Get-ChildItem -LiteralPath $ManifestDirectory -Filter "library-manifest-*.json" -File |
    Sort-Object -Property LastWriteTimeUtc, Name -Descending |
    Select-Object -First 1

  if ($null -eq $LatestManifest) {
    return $Lookup
  }

  $Lookup.manifestPath = $LatestManifest.FullName

  try {
    $ManifestData = Get-Content -LiteralPath $LatestManifest.FullName -Raw | ConvertFrom-Json
    foreach ($Entry in @($ManifestData.entries)) {
      if ($null -eq $Entry) {
        continue
      }

      $EntryHash = ""
      if ($Entry.contentHash) {
        $EntryHash = [string]$Entry.contentHash
      }

      if (-not [string]::IsNullOrWhiteSpace([string]$Entry.sourceId)) {
        $Lookup.bySourceId[[string]$Entry.sourceId] = $EntryHash
      }
      if (-not [string]::IsNullOrWhiteSpace([string]$Entry.sourcePath)) {
        $Lookup.bySourcePath[[string]$Entry.sourcePath] = $EntryHash
      }
    }
  } catch {
    Write-Warning ("Failed to parse latest manifest '{0}': {1}" -f $LatestManifest.FullName, $_.Exception.Message)
  }

  return $Lookup
}

function Get-ReviewStateCounts {
  param(
    [object[]]$Items,
    [string[]]$AllowedStates
  )

  $Counts = [ordered]@{}
  foreach ($State in $AllowedStates) {
    $Counts[$State] = 0
  }

  foreach ($ReviewItem in $Items) {
    $State = "pending_human_review"
    if ($ReviewItem.human_review -and $ReviewItem.human_review.state) {
      $State = [string]$ReviewItem.human_review.state
    }
    if ($AllowedStates -notcontains $State) {
      $State = "pending_human_review"
    }
    if (-not $Counts.Contains($State)) {
      $Counts[$State] = 0
    }
    $Counts[$State] += 1
  }

  return $Counts
}

$ConfigFile = Join-Path $Root "config/a-brain.json"
if (Test-Path -LiteralPath $ConfigFile) {
  $Config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
  if ($Config.dream.reviewStates) {
    $AllowedReviewStates = @($Config.dream.reviewStates)
  }
}

$ResolvedSourcePath = Resolve-InputPath -InputPath $SourcePath -RootPath $Root
if (-not (Test-Path -LiteralPath $ResolvedSourcePath)) {
  throw "Source path not found: $SourcePath"
}

$SourceFiles = @()
$Item = Get-Item -LiteralPath $ResolvedSourcePath
if ($Item.PSIsContainer) {
  $SourceFiles = @(
    Get-ChildItem -LiteralPath $ResolvedSourcePath -Recurse -File |
      Where-Object { @(".md", ".txt") -contains $_.Extension.ToLowerInvariant() } |
      Sort-Object -Property FullName |
      Select-Object -First $Limit
  )
} else {
  if (@(".md", ".txt") -contains $Item.Extension.ToLowerInvariant()) {
    $SourceFiles = @($Item)
  }
}

if ($SourceFiles.Count -eq 0) {
  Write-Output "No supported .md or .txt files found under: $ResolvedSourcePath"
  exit 0
}

$ManifestDir = Join-Path $Root "ingest/manifests"
$RunDir = Join-Path $Root "ingest/runs"
$ConceptDir = Join-Path $Root "ingest/candidates/concepts"
$NotesDir = Join-Path $Root "knowledge/notes"
$QueueFile = Join-Path $Root "dream/review/queue.json"
$StateFile = Join-Path $Root "dream/review/state.json"
$RunToken = Get-UniqueRunToken -BaseTime $Now -ManifestDirectory $ManifestDir -RunDirectory $RunDir
$Timestamp = $RunToken
$LatestManifestLookup = Get-LatestManifestLookup -ManifestDirectory $ManifestDir

$QueueData = [pscustomobject]@{
  schema = "a-brain-dream-review-queue-v1"
  items = @()
}

if (Test-Path -LiteralPath $QueueFile) {
  $QueueData = Get-Content -LiteralPath $QueueFile -Raw | ConvertFrom-Json
}

$ReviewItems = @($QueueData.items)
$ManifestEntries = @()
$RunSources = @()
$WriteOperations = @()
$AllWarnings = @()
$UsedNotePaths = @{}
$UsedConceptPaths = @{}
$UsedNewReviewIds = @{}

foreach ($ReviewItem in $ReviewItems) {
  if ($null -ne $ReviewItem -and -not [string]::IsNullOrWhiteSpace([string]$ReviewItem.id)) {
    $UsedNewReviewIds[[string]$ReviewItem.id] = 1
  }
}

foreach ($SourceFile in $SourceFiles) {
  $ReadResult = Read-TextWithUtf8Fallback -Path $SourceFile.FullName
  $Text = $ReadResult.text
  $Bytes = $ReadResult.bytes
  $ContentHash = Get-Sha256Hex -Bytes $Bytes
  $RelativePath = Get-RepoRelativePath -RootPath $Root -FullPath $SourceFile.FullName
  $StablePathHash = Get-StablePathHash -RelativePath $RelativePath
  $Frontmatter = Parse-SimpleFrontmatter -Text $Text
  $FrontmatterFields = $Frontmatter.fields
  $BodyText = $Frontmatter.body
  $SlugSeed = Get-SafeSlug -Value ([System.IO.Path]::GetFileNameWithoutExtension($SourceFile.Name)) -FallbackHash $ContentHash
  $GeneratedSourceId = "source-path-{0}-{1}" -f $SlugSeed, $StablePathHash
  $SourceId = if ([string]::IsNullOrWhiteSpace($FrontmatterFields["sourceId"])) { $GeneratedSourceId } else { [string]$FrontmatterFields["sourceId"] }
  $Title = if ([string]::IsNullOrWhiteSpace($FrontmatterFields["title"])) { [System.IO.Path]::GetFileNameWithoutExtension($SourceFile.Name) } else { [string]$FrontmatterFields["title"] }
  $SourceType = Get-SourceType -Extension $SourceFile.Extension -FrontmatterValue ([string]$FrontmatterFields["sourceType"])
  $PreviousHash = ""
  if ($LatestManifestLookup.bySourceId.ContainsKey($SourceId)) {
    $PreviousHash = [string]$LatestManifestLookup.bySourceId[$SourceId]
  } elseif ($LatestManifestLookup.bySourcePath.ContainsKey($RelativePath)) {
    $PreviousHash = [string]$LatestManifestLookup.bySourcePath[$RelativePath]
  }
  $HasPreviousHash = -not [string]::IsNullOrWhiteSpace($PreviousHash)
  $HashChanged = $HasPreviousHash -and (-not [string]::Equals($ContentHash, $PreviousHash, [System.StringComparison]::Ordinal))
  $DiffStatus = if (-not $HasPreviousHash) {
    "new"
  } elseif ($HashChanged) {
    "changed"
  } else {
    "unchanged"
  }
  $FirstParagraph = Get-FirstParagraph -Text $BodyText
  if ([string]::IsNullOrWhiteSpace($FirstParagraph)) {
    $FirstParagraph = "Imported from $RelativePath."
  }
  $Summary = $FirstParagraph
  if ($Summary.Length -gt 220) {
    $Summary = $Summary.Substring(0, 220).Trim() + "..."
  }

  $Warnings = @()
  if ([string]::IsNullOrWhiteSpace($FrontmatterFields["title"])) {
    $Warnings += "Frontmatter missing title; fallback to file name."
  }
  if ([string]::IsNullOrWhiteSpace($FrontmatterFields["sourceId"])) {
    $Warnings += "Frontmatter missing sourceId; generated fallback '$GeneratedSourceId'."
  }
  if ([string]::IsNullOrWhiteSpace($FrontmatterFields["sourceType"])) {
    $Warnings += "Frontmatter missing sourceType; inferred '$SourceType'."
  }
  if ([string]::IsNullOrWhiteSpace($FrontmatterFields["sourcePath"])) {
    $Warnings += "Frontmatter missing sourcePath; expected '$RelativePath'."
  } elseif ((([string]$FrontmatterFields["sourcePath"]).Replace('\', '/')) -ne $RelativePath) {
    $Warnings += "Frontmatter sourcePath '$($FrontmatterFields["sourcePath"])' does not match '$RelativePath'."
  }
  if ([string]::IsNullOrWhiteSpace($FrontmatterFields["contentHash"])) {
    $Warnings += "Frontmatter missing contentHash; computed '$ContentHash'."
  } elseif ([string]$FrontmatterFields["contentHash"] -ne $ContentHash) {
    $Warnings += "Frontmatter contentHash '$($FrontmatterFields["contentHash"])' does not match '$ContentHash'."
  }
  if (-not [string]::IsNullOrWhiteSpace($FrontmatterFields["sourceId"]) -and ([string]$FrontmatterFields["sourceId"] -ne $SourceId)) {
    $Warnings += "Frontmatter sourceId normalization changed the emitted value."
  }
  if (-not [string]::IsNullOrWhiteSpace($FrontmatterFields["title"]) -and ([string]$FrontmatterFields["title"] -ne $Title)) {
    $Warnings += "Frontmatter title normalization changed the emitted value."
  }
  if (-not [string]::IsNullOrWhiteSpace($FrontmatterFields["sourceType"]) -and ([string]$FrontmatterFields["sourceType"] -ne $SourceType)) {
    $Warnings += "Frontmatter sourceType normalization changed the emitted value."
  }

  $SourceIdSlug = Get-SafeSlug -Value $SourceId -FallbackHash $ContentHash
  $CandidateStem = "$SourceIdSlug-$StablePathHash"
  $NoteRelativePath = Get-UniquePathValue -BasePath "knowledge/notes/ingest-$CandidateStem.md" -UsedPaths $UsedNotePaths
  $ConceptRelativePath = Get-UniquePathValue -BasePath "ingest/candidates/concepts/concept-candidate-$CandidateStem.md" -UsedPaths $UsedConceptPaths
  $ExistingReviewItem = $null
  foreach ($ReviewItem in $ReviewItems) {
    $ReviewState = "pending_human_review"
    if ($ReviewItem.human_review -and $ReviewItem.human_review.state) {
      $ReviewState = [string]$ReviewItem.human_review.state
    }
    if (
      $ReviewItem.item_type -eq "ingest_candidate" -and
      $ReviewState -eq "pending_human_review" -and
      (
        $ReviewItem.source_id -eq $SourceId -or
        $ReviewItem.source_path -eq $RelativePath
      )
    ) {
      $ExistingReviewItem = $ReviewItem
      break
    }
  }

  $ReviewId = ""
  if ($null -ne $ExistingReviewItem) {
    $ReviewId = [string]$ExistingReviewItem.id
  } else {
    $ReviewIdBase = "review-{0}-{1}-{2}" -f $Timestamp, $SourceIdSlug, $StablePathHash
    $ReviewId = Get-UniqueStringValue -BaseValue $ReviewIdBase -UsedValues $UsedNewReviewIds
    $ExistingReviewItem = [pscustomobject]@{
      id = $ReviewId
      created_at = $IngestedAt
      item_type = "ingest_candidate"
      path = $ConceptRelativePath
      priority = "medium"
      reason = @("source_ingest_candidate", "needs_human_review")
      source_id = $SourceId
      source_path = $RelativePath
      source_hash = $ContentHash
      auto_review = [pscustomobject]@{
        model = ""
        verdict = ""
        risk = ""
      }
      human_review = [pscustomobject]@{
        state = "pending_human_review"
        reviewer = ""
        reviewed_at = ""
        decision = ""
        comment = ""
      }
    }
    $ReviewItems += $ExistingReviewItem
  }

  $ExistingReviewItem | Add-Member -NotePropertyName path -NotePropertyValue $ConceptRelativePath -Force
  $ExistingReviewItem | Add-Member -NotePropertyName priority -NotePropertyValue "medium" -Force
  $ExistingReviewItem | Add-Member -NotePropertyName source_id -NotePropertyValue $SourceId -Force
  $ExistingReviewItem | Add-Member -NotePropertyName source_path -NotePropertyValue $RelativePath -Force
  $ExistingReviewItem | Add-Member -NotePropertyName source_hash -NotePropertyValue $ContentHash -Force
  $ExistingReviewItem | Add-Member -NotePropertyName updated_at -NotePropertyValue $IngestedAt -Force
  $ExistingReviewItem | Add-Member -NotePropertyName reason -NotePropertyValue @("source_ingest_candidate", "needs_human_review") -Force
  if ($null -eq $ExistingReviewItem.human_review) {
    $ExistingReviewItem | Add-Member -NotePropertyName human_review -NotePropertyValue ([pscustomobject]@{}) -Force
  }
  $ExistingReviewItem.human_review | Add-Member -NotePropertyName state -NotePropertyValue "pending_human_review" -Force
  $ExistingReviewItem.human_review | Add-Member -NotePropertyName comment -NotePropertyValue "" -Force

  $ClaimTexts = @($Title)
  if ($Summary -ne $Title) {
    $ClaimTexts += $Summary
  }

  $NoteClaimsYaml = New-ClaimsYamlBlock -SourceId $SourceId -SourcePathValue $RelativePath -ClaimTexts $ClaimTexts -ConfidenceScore 45 -ClaimPrefix ("claim-" + $SourceIdSlug + "-note")
  $ConceptClaimsYaml = New-ClaimsYamlBlock -SourceId $SourceId -SourcePathValue $RelativePath -ClaimTexts $ClaimTexts -ConfidenceScore 40 -ClaimPrefix ("claim-" + $SourceIdSlug + "-concept")
  $ConceptSummary = "Source-driven concept candidate extracted from $SourceId. Review is required before promotion."

  $NoteContent = New-NoteCandidateContent -Title $Title -Summary $Summary -Updated $UpdatedDate -SourceId $SourceId -SourceHash $ContentHash -ReviewId $ReviewId -SourcePathValue $RelativePath -SourceType $SourceType -LastWriteTimeUtc $SourceFile.LastWriteTimeUtc.ToString("o") -ClaimsYaml $NoteClaimsYaml -ContentHash $ContentHash
  $ConceptContent = New-ConceptCandidateContent -Title $Title -Summary $ConceptSummary -Updated $UpdatedDate -SourceId $SourceId -SourceHash $ContentHash -ReviewId $ReviewId -SourcePathValue $RelativePath -ClaimsYaml $ConceptClaimsYaml -ContentHash $ContentHash

  $WriteOperations += [pscustomobject]@{ path = $NoteRelativePath; kind = "note_candidate"; content = $NoteContent }
  $WriteOperations += [pscustomobject]@{ path = $ConceptRelativePath; kind = "concept_candidate"; content = $ConceptContent }

  $ManifestEntry = [ordered]@{
    sourceId = $SourceId
    title = $Title
    sourceType = $SourceType
    sourcePath = $RelativePath
    stablePathHash = $StablePathHash
    contentHash = $ContentHash
    previousHash = $PreviousHash
    diffStatus = $DiffStatus
    hashChanged = $HashChanged
    bytes = $Bytes.Length
    chars = $Text.Length
    encoding = $ReadResult.encoding
    lastWriteTimeUtc = $SourceFile.LastWriteTimeUtc.ToString("o")
    noteCandidatePath = $NoteRelativePath
    conceptCandidatePath = $ConceptRelativePath
    reviewItemId = $ReviewId
    warnings = @($Warnings)
  }
  $ManifestEntries += [pscustomobject]$ManifestEntry

  $RunSources += [pscustomobject]@{
    sourceId = $SourceId
    sourcePath = $RelativePath
    stablePathHash = $StablePathHash
    diffStatus = $DiffStatus
    noteCandidatePath = $NoteRelativePath
    conceptCandidatePath = $ConceptRelativePath
    reviewItemId = $ReviewId
    warnings = @($Warnings)
  }

  if ($Warnings.Count -gt 0) {
    $AllWarnings += [pscustomobject]@{
      sourceId = $SourceId
      sourcePath = $RelativePath
      messages = @($Warnings)
    }
  }
}

$Counts = Get-ReviewStateCounts -Items $ReviewItems -AllowedStates $AllowedReviewStates
$QueueSchema = "a-brain-dream-review-queue-v1"
if ($QueueData.schema) {
  $QueueSchema = [string]$QueueData.schema
}
$QueueOutput = [ordered]@{
  schema = $QueueSchema
  items = $ReviewItems
}
$StateOutput = [ordered]@{
  schema = "a-brain-dream-review-state-v1"
  updatedAt = $IngestedAt
  counts = $Counts
}
$ManifestOutput = [ordered]@{
  schema = "a-brain-ingest-library-manifest-v1"
  generatedAt = $IngestedAt
  sourcePath = (Get-RepoRelativePath -RootPath $Root -FullPath $ResolvedSourcePath)
  limit = $Limit
  sourceCount = $ManifestEntries.Count
  entries = $ManifestEntries
}
$ManifestRelativePath = "ingest/manifests/library-manifest-$Timestamp.json"
$ManifestPath = Join-Path $Root ($ManifestRelativePath -replace '/', '\')
$RunRelativePath = "ingest/runs/ingest-library-run-$Timestamp.json"
$RunPath = Join-Path $Root ($RunRelativePath -replace '/', '\')
$RunOutput = [ordered]@{
  schema = "a-brain-ingest-library-run-v1"
  runId = "ingest-library-$Timestamp"
  startedAt = $IngestedAt
  completedAt = $IngestedAt
  dryRun = [bool]$DryRun
  sourcePath = (Get-RepoRelativePath -RootPath $Root -FullPath $ResolvedSourcePath)
  limit = $Limit
  manifestPath = $ManifestRelativePath
  queuePath = "dream/review/queue.json"
  statePath = "dream/review/state.json"
  writeCount = $WriteOperations.Count + 4
  sourceCount = $RunSources.Count
  sources = $RunSources
  warnings = $AllWarnings
}

if ($DryRun) {
  Write-Output "A-Brain ingest-library dry run"
  Write-Output ("source path: {0}" -f (Get-RepoRelativePath -RootPath $Root -FullPath $ResolvedSourcePath))
  Write-Output ("sources: {0}" -f $RunSources.Count)
  Write-Output ("planned manifest: {0}" -f $ManifestRelativePath)
  Write-Output ("planned run file: {0}" -f $RunRelativePath)
  foreach ($Source in $RunSources) {
    Write-Output ("- {0} [{1}]" -f $Source.sourceId, $Source.diffStatus)
    Write-Output ("  note: {0}" -f $Source.noteCandidatePath)
    Write-Output ("  concept: {0}" -f $Source.conceptCandidatePath)
    Write-Output ("  review item: {0}" -f $Source.reviewItemId)
    if ($Source.warnings.Count -gt 0) {
      foreach ($Warning in $Source.warnings) {
        Write-Output ("  warning: {0}" -f $Warning)
      }
    }
  }
  exit 0
}

foreach ($PathToEnsure in @($ManifestPath, $RunPath, $QueueFile, $StateFile, (Join-Path $NotesDir "placeholder"), (Join-Path $ConceptDir "placeholder"))) {
  Ensure-ParentDirectory -Path $PathToEnsure
}

foreach ($Operation in $WriteOperations) {
  $FullPath = Join-Path $Root ($Operation.path -replace '/', '\')
  Ensure-ParentDirectory -Path $FullPath
  [System.IO.File]::WriteAllText($FullPath, [string]$Operation.content, (New-Object System.Text.UTF8Encoding($false)))
}

$QueueJson = $QueueOutput | ConvertTo-Json -Depth 12
$StateJson = $StateOutput | ConvertTo-Json -Depth 8
$ManifestJson = $ManifestOutput | ConvertTo-Json -Depth 12
$RunJson = $RunOutput | ConvertTo-Json -Depth 12

[System.IO.File]::WriteAllText($QueueFile, $QueueJson, (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($StateFile, $StateJson, (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($ManifestPath, $ManifestJson, (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($RunPath, $RunJson, (New-Object System.Text.UTF8Encoding($false)))

Write-Output ("A-Brain ingest-library manifest: {0}" -f $ManifestRelativePath)
Write-Output ("A-Brain ingest-library run: {0}" -f $RunRelativePath)
Write-Output ("Sources processed: {0}" -f $RunSources.Count)
foreach ($Source in $RunSources) {
  Write-Output ("- {0} -> {1}" -f $Source.sourceId, $Source.noteCandidatePath)
}
