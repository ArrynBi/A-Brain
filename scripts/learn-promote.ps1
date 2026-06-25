param(
  [Parameter(Mandatory = $true)]
  [string]$Candidate,

  [Parameter(Mandatory = $true)]
  [ValidateSet("accepted", "promoted")]
  [string]$Decision,

  [switch]$InstallRuntime
)

$ErrorActionPreference = "Stop"

if ($InstallRuntime) {
  throw "learn-promote v1 does not auto-install runtime skills. Remove -InstallRuntime and promote the document only."
}

$Root = Split-Path -Parent $PSScriptRoot
$Now = Get-Date
$UpdatedDate = $Now.ToString("yyyy-MM-dd")
$PromotedAt = $Now.ToString("o")
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
    [string]$PathValue,
    [string]$RootPath
  )

  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    throw "-Candidate cannot be empty."
  }

  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }

  $Candidates = @(
    $PathValue,
    (Join-Path (Get-Location).Path $PathValue),
    (Join-Path $RootPath $PathValue)
  )

  foreach ($CandidatePathValue in $Candidates) {
    if (Test-Path -LiteralPath $CandidatePathValue) {
      return [System.IO.Path]::GetFullPath($CandidatePathValue)
    }
  }

  return [System.IO.Path]::GetFullPath((Join-Path $RootPath $PathValue))
}

function Get-NormalizedRelativeOrAbsolutePath {
  param(
    [string]$RootPath,
    [string]$FullPath
  )

  $NormalizedRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
  $NormalizedFull = [System.IO.Path]::GetFullPath($FullPath)

  if ($NormalizedFull.Length -gt $NormalizedRoot.Length -and $NormalizedFull.StartsWith($NormalizedRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    $RootUri = New-Object System.Uri(($NormalizedRoot + "\"))
    $FileUri = New-Object System.Uri($NormalizedFull)
    $Relative = $RootUri.MakeRelativeUri($FileUri).ToString()
    return [System.Uri]::UnescapeDataString($Relative).Replace('\', '/')
  }

  return $NormalizedFull.Replace('\', '/')
}

function Read-TextWithUtf8Fallback {
  param([string]$Path)

  $Bytes = [System.IO.File]::ReadAllBytes($Path)
  $Utf8 = New-Object System.Text.UTF8Encoding($false, $true)
  try {
    $Text = $Utf8.GetString($Bytes)
  } catch {
    $Text = [System.Text.Encoding]::Default.GetString($Bytes)
  }

  return $Text
}

function Parse-FrontmatterValue {
  param([string]$RawValue)

  if ($null -eq $RawValue) {
    return ""
  }

  $Value = $RawValue.Trim()
  if (($Value.StartsWith("'") -and $Value.EndsWith("'")) -or ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
    return $Value.Substring(1, $Value.Length - 2)
  }

  if ($Value.StartsWith("[") -and $Value.EndsWith("]")) {
    $Inner = $Value.Substring(1, $Value.Length - 2).Trim()
    if ([string]::IsNullOrWhiteSpace($Inner)) {
      return @()
    }

    $Parts = $Inner -split ","
    $Values = @()
    foreach ($Part in $Parts) {
      $Item = $Part.Trim()
      if (($Item.StartsWith("'") -and $Item.EndsWith("'")) -or ($Item.StartsWith('"') -and $Item.EndsWith('"'))) {
        $Item = $Item.Substring(1, $Item.Length - 2)
      }
      if (-not [string]::IsNullOrWhiteSpace($Item)) {
        $Values += $Item
      }
    }
    return @($Values)
  }

  return $Value
}

function Parse-SimpleFrontmatter {
  param([string]$Text)

  $Result = [ordered]@{
    fields = [ordered]@{}
    body = $Text
    raw = $null
  }

  if ($Text -notmatch "^(---\r?\n)([\s\S]*?)\r?\n---\r?\n?") {
    return [pscustomobject]$Result
  }

  $FrontmatterBlock = $Matches[2]
  $BodyStart = $Matches[0].Length
  $Fields = [ordered]@{}

  foreach ($Line in ($FrontmatterBlock -split "\r?\n")) {
    if ($Line -match "^\s*([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*$") {
      $Fields[$Matches[1]] = Parse-FrontmatterValue -RawValue $Matches[2]
    }
  }

  $Result.fields = $Fields
  $Result.body = $Text.Substring($BodyStart)
  $Result.raw = $FrontmatterBlock
  return [pscustomobject]$Result
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
      return "item"
    }
    return $FallbackHash.Substring(0, [Math]::Min(8, $FallbackHash.Length)).ToLowerInvariant()
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

function Ensure-ParentDirectory {
  param([string]$Path)

  $Parent = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($Parent) -and -not (Test-Path -LiteralPath $Parent)) {
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null
  }
}

function Test-IsPathInsideDirectory {
  param(
    [string]$PathValue,
    [string]$DirectoryValue
  )

  $FullPath = [System.IO.Path]::GetFullPath($PathValue)
  $FullDirectory = [System.IO.Path]::GetFullPath($DirectoryValue).TrimEnd('\') + "\"
  return $FullPath.StartsWith($FullDirectory, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-UniqueFilePath {
  param([string]$PathValue)

  if (-not (Test-Path -LiteralPath $PathValue)) {
    return $PathValue
  }

  $Directory = Split-Path -Parent $PathValue
  $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($PathValue)
  $Extension = [System.IO.Path]::GetExtension($PathValue)
  $Attempt = 2

  while ($true) {
    $CandidatePathValue = Join-Path $Directory ("{0}-{1}{2}" -f $BaseName, $Attempt, $Extension)
    if (-not (Test-Path -LiteralPath $CandidatePathValue)) {
      return $CandidatePathValue
    }
    $Attempt += 1
  }
}

function Get-FrontmatterValueOrDefault {
  param(
    [System.Collections.IDictionary]$Fields,
    [string]$Key,
    [object]$DefaultValue
  )

  if ($Fields.Contains($Key)) {
    return $Fields[$Key]
  }

  return $DefaultValue
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

$CandidatePath = Resolve-InputPath -PathValue $Candidate -RootPath $Root
if (-not (Test-Path -LiteralPath $CandidatePath)) {
  throw "Candidate not found: $Candidate"
}

$CandidateItem = Get-Item -LiteralPath $CandidatePath
if ($CandidateItem.PSIsContainer) {
  throw "learn-promote expects one candidate markdown file."
}

if ($CandidateItem.Extension.ToLowerInvariant() -ne ".md") {
  throw "learn-promote expects a markdown candidate under learn/candidates."
}

$CandidatesRoot = Join-Path $Root "learn/candidates"
if (-not (Test-IsPathInsideDirectory -PathValue $CandidatePath -DirectoryValue $CandidatesRoot)) {
  throw "learn-promote only accepts candidates from learn/candidates. Refusing: $Candidate"
}

$CandidateText = Read-TextWithUtf8Fallback -Path $CandidatePath
$ParsedCandidate = Parse-SimpleFrontmatter -Text $CandidateText
$Fields = $ParsedCandidate.fields
$Body = [string]$ParsedCandidate.body

$TitleValue = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "title" -DefaultValue ([System.IO.Path]::GetFileNameWithoutExtension($CandidateItem.Name)))
$FallbackHash = ""
if ($Fields.Contains("sourceHashes") -and $Fields["sourceHashes"] -is [System.Array] -and $Fields["sourceHashes"].Count -gt 0) {
  $FallbackHash = [string]$Fields["sourceHashes"][0]
} elseif ($Fields.Contains("learnSourceHash")) {
  $FallbackHash = [string]$Fields["learnSourceHash"]
}
$Slug = Get-SafeSlug -Value $TitleValue -FallbackHash $FallbackHash
$SkillRelativePath = "knowledge/skills/{0}.md" -f $Slug
$SkillPath = Join-Path $Root ($SkillRelativePath -replace '/', '\')
$SkillPath = Get-UniqueFilePath -PathValue $SkillPath
$SkillRelativePath = Get-NormalizedRelativeOrAbsolutePath -RootPath $Root -FullPath $SkillPath
$PromotionRelativePath = "learn/promoted/{0}-{1}.md" -f $Slug, $Now.ToString("yyyyMMdd-HHmmss-fff")
$PromotionPath = Join-Path $Root ($PromotionRelativePath -replace '/', '\')
$PromotionPath = Get-UniqueFilePath -PathValue $PromotionPath
$PromotionRelativePath = Get-NormalizedRelativeOrAbsolutePath -RootPath $Root -FullPath $PromotionPath

$TitleLine = Format-YamlString -Value $TitleValue
$TypeLine = Format-YamlString -Value ([string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "type" -DefaultValue "skill"))
$TagsLine = Format-YamlInlineArray -Values @((Get-FrontmatterValueOrDefault -Fields $Fields -Key "tags" -DefaultValue @()))
$SourceLine = Format-YamlString -Value ([string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "source" -DefaultValue "local"))
$SummaryLine = Format-YamlString -Value ([string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "summary" -DefaultValue ("Promoted learn skill for " + $TitleValue)))
$ConfidenceScore = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "confidenceScore" -DefaultValue "40")
$ConfidenceFormulaVersion = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "confidenceFormulaVersion" -DefaultValue "a-brain-confidence-v1")
$ConfidenceAggregation = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "confidenceAggregation" -DefaultValue "p25")
$ClaimSetPath = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "claimSetPath" -DefaultValue "")
$ConfidenceClaimRefs = Format-YamlInlineArray -Values @((Get-FrontmatterValueOrDefault -Fields $Fields -Key "confidenceClaimRefs" -DefaultValue @()))
$ProvenanceState = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "provenanceState" -DefaultValue "extracted")
$InferenceState = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "inferenceState" -DefaultValue "inferred")
$CitationCoverage = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "citationCoverage" -DefaultValue "partial")
$SourceIds = Format-YamlInlineArray -Values @((Get-FrontmatterValueOrDefault -Fields $Fields -Key "sourceIds" -DefaultValue @()))
$ContradictedBy = Format-YamlInlineArray -Values @((Get-FrontmatterValueOrDefault -Fields $Fields -Key "contradictedBy" -DefaultValue @()))
$Supersedes = Format-YamlInlineArray -Values @((Get-FrontmatterValueOrDefault -Fields $Fields -Key "supersedes" -DefaultValue @()))
$ReviewQueueRefs = Format-YamlInlineArray -Values @((Get-FrontmatterValueOrDefault -Fields $Fields -Key "reviewQueueRefs" -DefaultValue @()))
$ModelId = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "modelId" -DefaultValue "")
$PromptVersion = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "promptVersion" -DefaultValue "")
$ContentHash = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "contentHash" -DefaultValue "")
$SourceHashes = Format-YamlInlineArray -Values @((Get-FrontmatterValueOrDefault -Fields $Fields -Key "sourceHashes" -DefaultValue @()))
$LearnInputType = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "learnInputType" -DefaultValue "")
$LearnKind = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "learnKind" -DefaultValue "")
$LearnSourcePath = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "learnSourcePath" -DefaultValue "")
$LearnSourceHash = [string](Get-FrontmatterValueOrDefault -Fields $Fields -Key "learnSourceHash" -DefaultValue "")

$PromotedFrontmatter = @"
---
title: $TitleLine
type: $TypeLine
tags: $TagsLine
source: $SourceLine
updated: $UpdatedDate
summary: $SummaryLine
status: promoted
confidenceScore: $ConfidenceScore
confidenceFormulaVersion: $(Format-YamlString -Value $ConfidenceFormulaVersion)
confidenceAggregation: $(Format-YamlString -Value $ConfidenceAggregation)
claimSetPath: $(if ([string]::IsNullOrWhiteSpace($ClaimSetPath)) { "" } else { Format-YamlString -Value $ClaimSetPath })
confidenceClaimRefs: $ConfidenceClaimRefs
provenanceState: $(Format-YamlString -Value $ProvenanceState)
inferenceState: $(Format-YamlString -Value $InferenceState)
citationCoverage: $(Format-YamlString -Value $CitationCoverage)
reviewState: promoted
schemaState: compliant
sourceIds: $SourceIds
contradictedBy: $ContradictedBy
supersedes: $Supersedes
promoted_to:
reviewQueueRefs: $ReviewQueueRefs
modelId: $(if ([string]::IsNullOrWhiteSpace($ModelId)) { "" } else { Format-YamlString -Value $ModelId })
promptVersion: $(if ([string]::IsNullOrWhiteSpace($PromptVersion)) { "" } else { Format-YamlString -Value $PromptVersion })
contentHash: $(if ([string]::IsNullOrWhiteSpace($ContentHash)) { "" } else { Format-YamlString -Value $ContentHash })
sourceHashes: $SourceHashes
learnInputType: $(if ([string]::IsNullOrWhiteSpace($LearnInputType)) { "" } else { Format-YamlString -Value $LearnInputType })
learnKind: $(if ([string]::IsNullOrWhiteSpace($LearnKind)) { "" } else { Format-YamlString -Value $LearnKind })
learnSourcePath: $(if ([string]::IsNullOrWhiteSpace($LearnSourcePath)) { "" } else { Format-YamlString -Value $LearnSourcePath })
learnSourceHash: $(if ([string]::IsNullOrWhiteSpace($LearnSourceHash)) { "" } else { Format-YamlString -Value $LearnSourceHash })
---
"@

$PromotedContent = $PromotedFrontmatter + "`r`n" + $Body.TrimStart("`r", "`n")

$CandidateRelativePath = Get-NormalizedRelativeOrAbsolutePath -RootPath $Root -FullPath $CandidatePath
$PromotedBodyHash = Get-Sha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Body))
$PromotionRecord = @"
# Learn Promotion Record

- Candidate: `$CandidateRelativePath`
- Decision: `$Decision`
- Promoted at: `$PromotedAt`
- Published skill: `$SkillRelativePath`
- Runtime install: disabled in v1
- Candidate body hash: `$PromotedBodyHash`

## Candidate Body

$Body
"@

$QueueFile = Join-Path $Root "dream/review/queue.json"
$StateFile = Join-Path $Root "dream/review/state.json"
$QueueData = [pscustomobject]@{
  schema = "a-brain-dream-review-queue-v1"
  items = @()
}
if (Test-Path -LiteralPath $QueueFile) {
  $QueueData = Get-Content -LiteralPath $QueueFile -Raw | ConvertFrom-Json
}
$ReviewItems = @($QueueData.items)

$MatchedReviewItem = $null
foreach ($ReviewItem in $ReviewItems) {
  if ($ReviewItem.item_type -eq "learn_candidate" -and $ReviewItem.path -eq $CandidateRelativePath) {
    $MatchedReviewItem = $ReviewItem
    break
  }
}

if ($null -ne $MatchedReviewItem -and $MatchedReviewItem.human_review -and $MatchedReviewItem.human_review.state -eq "promoted") {
  throw "Candidate is already promoted: $CandidateRelativePath"
}

if ($null -ne $MatchedReviewItem) {
  if ($null -eq $MatchedReviewItem.human_review) {
    $MatchedReviewItem | Add-Member -NotePropertyName human_review -NotePropertyValue ([pscustomobject]@{}) -Force
  }
  $MatchedReviewItem.human_review | Add-Member -NotePropertyName state -NotePropertyValue "promoted" -Force
  $MatchedReviewItem.human_review | Add-Member -NotePropertyName reviewed_at -NotePropertyValue $PromotedAt -Force
  $MatchedReviewItem.human_review | Add-Member -NotePropertyName decision -NotePropertyValue $Decision -Force
  $MatchedReviewItem.human_review | Add-Member -NotePropertyName comment -NotePropertyValue ("Published to " + $SkillRelativePath) -Force
  $MatchedReviewItem | Add-Member -NotePropertyName updated_at -NotePropertyValue $PromotedAt -Force
}

$StateOutput = [ordered]@{
  schema = "a-brain-dream-review-state-v1"
  updatedAt = $PromotedAt
  counts = (Get-ReviewStateCounts -Items $ReviewItems -AllowedStates $AllowedReviewStates)
}

Ensure-ParentDirectory -Path $SkillPath
Ensure-ParentDirectory -Path $PromotionPath
Ensure-ParentDirectory -Path $QueueFile
Ensure-ParentDirectory -Path $StateFile
[System.IO.File]::WriteAllText($SkillPath, $PromotedContent, (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($PromotionPath, $PromotionRecord, (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($QueueFile, (([ordered]@{ schema = $(if ($QueueData.schema) { [string]$QueueData.schema } else { "a-brain-dream-review-queue-v1" }); items = $ReviewItems }) | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($StateFile, ($StateOutput | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

Write-Output ("A-Brain learn-promote: {0}" -f $SkillRelativePath)
Write-Output ("promotion record: {0}" -f $PromotionRelativePath)
Write-Output ("candidate: {0}" -f $CandidateRelativePath)
