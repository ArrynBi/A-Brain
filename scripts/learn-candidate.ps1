param(
  [Parameter(Mandatory = $true)]
  [string]$InputPath,

  [Parameter(Mandatory = $true)]
  [ValidateSet("source", "note", "process", "skill")]
  [string]$InputType,

  [string]$Title = "",

  [ValidateSet("skill", "process_skill", "skill_improvement", "agent_rule")]
  [string]$Kind = "skill"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Now = Get-Date
$UpdatedDate = $Now.ToString("yyyy-MM-dd")
$CreatedAt = $Now.ToString("o")
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
    throw "-InputPath cannot be empty."
  }

  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }

  $Candidates = @(
    $PathValue,
    (Join-Path (Get-Location).Path $PathValue),
    (Join-Path $RootPath $PathValue)
  )

  foreach ($Candidate in $Candidates) {
    if (Test-Path -LiteralPath $Candidate) {
      return [System.IO.Path]::GetFullPath($Candidate)
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

function Get-Sha256HexFromString {
  param([string]$Value)

  if ($null -eq $Value) {
    $Value = ""
  }

  $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  return Get-Sha256Hex -Bytes $Bytes
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
    fields = @{}
    body = $Text
    raw = $null
  }

  if ($Text -notmatch "^(---\r?\n)([\s\S]*?)\r?\n---\r?\n?") {
    return [pscustomobject]$Result
  }

  $FrontmatterBlock = $Matches[2]
  $BodyStart = $Matches[0].Length
  $Fields = @{}

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

function Get-FirstMarkdownHeading {
  param([string]$Text)

  foreach ($Line in ($Text -split "\r?\n")) {
    if ($Line -match "^\s*#\s+(.+?)\s*$") {
      return $Matches[1].Trim()
    }
  }

  return ""
}

function Get-Headings {
  param(
    [string]$Text,
    [int]$Limit = 5
  )

  $Items = @()
  foreach ($Line in ($Text -split "\r?\n")) {
    if ($Line -match "^\s*#{1,6}\s+(.+?)\s*$") {
      $Items += $Matches[1].Trim()
      if ($Items.Count -ge $Limit) {
        break
      }
    }
  }

  return @($Items)
}

function Get-FirstNonEmptyLine {
  param([string]$Text)

  foreach ($Line in ($Text -split "\r?\n")) {
    $Clean = ($Line -replace "\s+", " ").Trim()
    if (-not [string]::IsNullOrWhiteSpace($Clean)) {
      return $Clean
    }
  }

  return ""
}

function Get-FirstParagraph {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return ""
  }

  $Normalized = $Text -replace "\r", ""
  $Paragraphs = $Normalized -split "\n\s*\n"
  foreach ($Paragraph in $Paragraphs) {
    if ($Paragraph -match "^\s*#{1,6}\s+") {
      continue
    }
    $Clean = ($Paragraph -replace "\s+", " ").Trim()
    $Clean = $Clean.Trim('#').Trim()
    if (-not [string]::IsNullOrWhiteSpace($Clean)) {
      return $Clean
    }
  }

  return ""
}

function Limit-Text {
  param(
    [string]$Text,
    [int]$MaxLength
  )

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return ""
  }

  $Normalized = ($Text -replace "\s+", " ").Trim()
  if ($Normalized.Length -le $MaxLength) {
    return $Normalized
  }

  return $Normalized.Substring(0, $MaxLength).Trim() + "..."
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

function Get-SourceIds {
  param(
    [hashtable]$Fields,
    [string]$FallbackId
  )

  if ($Fields.ContainsKey("sourceIds")) {
    $Value = $Fields["sourceIds"]
    if ($Value -is [System.Array]) {
      $Result = @($Value | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
      if ($Result.Count -gt 0) {
        return $Result
      }
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$Value)) {
      return @([string]$Value)
    }
  }

  if ($Fields.ContainsKey("sourceId") -and -not [string]::IsNullOrWhiteSpace([string]$Fields["sourceId"])) {
    return @([string]$Fields["sourceId"])
  }

  return @($FallbackId)
}

function Get-SourceHashes {
  param(
    [hashtable]$Fields,
    [string]$FallbackHash
  )

  if ($Fields.ContainsKey("sourceHashes")) {
    $Value = $Fields["sourceHashes"]
    if ($Value -is [System.Array]) {
      $Result = @($Value | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
      if ($Result.Count -gt 0) {
        return $Result
      }
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$Value)) {
      return @([string]$Value)
    }
  }

  if ($Fields.ContainsKey("contentHash") -and -not [string]::IsNullOrWhiteSpace([string]$Fields["contentHash"])) {
    return @([string]$Fields["contentHash"])
  }

  return @($FallbackHash)
}

function Get-KindDescription {
  param([string]$KindValue)

  switch ($KindValue) {
    "process_skill" { return "process plus skill draft" }
    "skill_improvement" { return "skill improvement draft" }
    "agent_rule" { return "narrow agent rule draft" }
    default { return "reusable skill draft" }
  }
}

function Get-InputTypeUsageHint {
  param([string]$InputTypeValue)

  switch ($InputTypeValue) {
    "source" { return "Turn an external or raw source into reviewable reusable guidance." }
    "note" { return "Distill a local note into a reusable operating pattern." }
    "process" { return "Formalize a repeatable process into a reusable procedure." }
    "skill" { return "Package or improve an existing skill without runtime install." }
    default { return "Create a reviewable learn candidate from one source file." }
  }
}

function New-CandidateContent {
  param(
    [string]$TitleValue,
    [string]$SummaryValue,
    [string]$UpdatedValue,
    [string]$InputTypeValue,
    [string]$KindValue,
    [string]$SourcePathValue,
    [string]$SourceHashValue,
    [string[]]$SourceIdsValue,
    [string[]]$SourceHashesValue,
    [string]$ReviewIdValue,
    [string]$TitleInferenceValue,
    [string[]]$HeadingValues,
    [string]$ExcerptValue
  )

  $Tags = Format-YamlInlineArray -Values @("learn", $InputTypeValue, $KindValue)
  $SourceIds = Format-YamlInlineArray -Values $SourceIdsValue
  $SourceHashes = Format-YamlInlineArray -Values $SourceHashesValue
  $ReviewRefs = Format-YamlInlineArray -Values @($ReviewIdValue)
  $QuotedTitle = Format-YamlString -Value $TitleValue
  $QuotedSummary = Format-YamlString -Value $SummaryValue
  $QuotedPath = Format-YamlString -Value $SourcePathValue
  $QuotedHash = Format-YamlString -Value $SourceHashValue
  $Code = [char]96
  $HeadingLine = if ($HeadingValues.Count -gt 0) {
    ($HeadingValues | ForEach-Object { "$Code$_$Code" }) -join ", "
  } else {
    "_none_"
  }
  $SkillDescription = Get-KindDescription -KindValue $KindValue
  $UsageHint = Get-InputTypeUsageHint -InputTypeValue $InputTypeValue
  $ExcerptLine = if ([string]::IsNullOrWhiteSpace($ExcerptValue)) { "_none_" } else { $ExcerptValue }

  return @"
---
title: $QuotedTitle
type: skill
tags: $Tags
source: local
updated: $UpdatedValue
summary: $QuotedSummary
status: fresh
confidenceScore: 40
confidenceFormulaVersion: a-brain-confidence-v1
confidenceAggregation: p25
claimSetPath:
confidenceClaimRefs: []
provenanceState: extracted
inferenceState: inferred
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
contentHash:
sourceHashes: $SourceHashes
learnInputType: $(Format-YamlString -Value $InputTypeValue)
learnKind: $(Format-YamlString -Value $KindValue)
learnSourcePath: $QuotedPath
learnSourceHash: $QuotedHash
---

# $TitleValue

## Summary

This learn candidate is a deterministic $SkillDescription derived from $Code$InputTypeValue$Code input $Code$SourcePathValue$Code. It is queued for human review and manual promotion only.

- Source summary: $SummaryValue
- Title inference: $TitleInferenceValue
- Review gate: ${Code}pending_human_review${Code} in ${Code}dream/review${Code}

## Source

- Input path: $Code$SourcePathValue$Code
- Input type: $Code$InputTypeValue$Code
- Kind: $Code$KindValue$Code
- Source ids: $(if ($SourceIdsValue.Count -gt 0) { ($SourceIdsValue -join ", ") } else { "_none_" })
- Source hash: $Code$SourceHashValue$Code
- Headings: $HeadingLine
- Excerpt: $ExcerptLine

## Candidate Skill

- Draft type: $SkillDescription
- Intent: Promote repeatable guidance from this $Code$InputTypeValue$Code into a human-reviewed skill document.
- Use when: $UsageHint
- Inputs:
  - One markdown or text file at $Code$SourcePathValue$Code
  - Stable source hash $Code$SourceHashValue$Code
  - Human decision before promotion
- Procedure:
  1. Read the source file and keep the extracted scope bounded to the file.
  2. Reuse headings, summary text, and explicit source facts before adding any inference.
  3. Keep the output in candidate form until a human chooses ${Code}accepted${Code} or ${Code}promoted${Code}.
  4. Publish only to ${Code}knowledge/skills${Code} during manual promote.
- Guardrails:
  - No LLM rewrite in v1 candidate generation.
  - No automatic runtime skill install.
  - No secondary review queue under ${Code}learn${Code}.

## Usage Draft

- Trigger: "learn from $TitleValue as $KindValue"
- Review queue path: ${Code}dream/review/queue.json${Code}
- Candidate path target: ${Code}learn/candidates${Code}
- Promotion target: ${Code}knowledge/skills/$(Get-SafeSlug -Value $TitleValue -FallbackHash $SourceHashValue).md${Code}
- Runtime install: disabled in v1

## Review Checklist

- [ ] The title and summary are grounded in the source file.
- [ ] The selected input type and kind are correct.
- [ ] The excerpt and headings are enough to justify the draft.
- [ ] Promotion should write only to ${Code}knowledge/skills${Code} and ${Code}learn/promoted${Code}.
- [ ] Runtime skill installation remains disabled.
"@
}

$ConfigFile = Join-Path $Root "config/a-brain.json"
if (Test-Path -LiteralPath $ConfigFile) {
  $Config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
  if ($Config.dream.reviewStates) {
    $AllowedReviewStates = @($Config.dream.reviewStates)
  }
}

$ResolvedInputPath = Resolve-InputPath -PathValue $InputPath -RootPath $Root
if (-not (Test-Path -LiteralPath $ResolvedInputPath)) {
  throw "Input path not found: $InputPath"
}

$InputItem = Get-Item -LiteralPath $ResolvedInputPath
if ($InputItem.PSIsContainer) {
  throw "learn-candidate only supports one .md or .txt file, not a directory."
}

$Extension = $InputItem.Extension.ToLowerInvariant()
if (@(".md", ".txt") -notcontains $Extension) {
  throw "Unsupported input extension '$Extension'. Only .md and .txt are allowed."
}

$CandidatesDir = Join-Path $Root "learn/candidates"
$QueueFile = Join-Path $Root "dream/review/queue.json"
$StateFile = Join-Path $Root "dream/review/state.json"

$ReadResult = Read-TextWithUtf8Fallback -Path $ResolvedInputPath
$Text = $ReadResult.text
$SourceHash = Get-Sha256Hex -Bytes $ReadResult.bytes
$SourcePathValue = Get-NormalizedRelativeOrAbsolutePath -RootPath $Root -FullPath $ResolvedInputPath
$Frontmatter = Parse-SimpleFrontmatter -Text $Text
$Fields = $Frontmatter.fields
$BodyText = [string]$Frontmatter.body
$HeadingTitle = Get-FirstMarkdownHeading -Text $BodyText
$FirstNonEmpty = Get-FirstNonEmptyLine -Text $BodyText
$InferredTitle = ""
$TitleInference = ""

if (-not [string]::IsNullOrWhiteSpace($Title)) {
  $InferredTitle = $Title.Trim()
  $TitleInference = "parameter"
} elseif ($Fields.ContainsKey("title") -and -not [string]::IsNullOrWhiteSpace([string]$Fields["title"])) {
  $InferredTitle = [string]$Fields["title"]
  $TitleInference = "frontmatter.title"
} elseif (-not [string]::IsNullOrWhiteSpace($HeadingTitle)) {
  $InferredTitle = $HeadingTitle
  $TitleInference = "markdown_heading"
} elseif (-not [string]::IsNullOrWhiteSpace($FirstNonEmpty)) {
  $InferredTitle = $FirstNonEmpty
  $TitleInference = "first_non_empty_line"
} else {
  $InferredTitle = [System.IO.Path]::GetFileNameWithoutExtension($InputItem.Name)
  $TitleInference = "file_name"
}

$Excerpt = Get-FirstParagraph -Text $BodyText
if ([string]::IsNullOrWhiteSpace($Excerpt)) {
  $Excerpt = Get-FirstParagraph -Text $Text
}
$Excerpt = Limit-Text -Text $Excerpt -MaxLength 220
if ([string]::IsNullOrWhiteSpace($Excerpt)) {
  $Excerpt = "No non-empty paragraph was extracted from the source body."
}

$FallbackSourceId = "learn-source-{0}-{1}" -f (Get-SafeSlug -Value ([System.IO.Path]::GetFileNameWithoutExtension($InputItem.Name)) -FallbackHash $SourceHash), (Get-Sha256HexFromString -Value $SourcePathValue).Substring(0, 10)
$SourceIds = Get-SourceIds -Fields $Fields -FallbackId $FallbackSourceId
$SourceHashes = Get-SourceHashes -Fields $Fields -FallbackHash $SourceHash
$HeadingValues = Get-Headings -Text $BodyText
$Summary = Limit-Text -Text ("Deterministic learn candidate from {0} {1} for {2}. {3}" -f $InputType, $SourcePathValue, $Kind, $Excerpt) -MaxLength 220
$Slug = Get-SafeSlug -Value $InferredTitle -FallbackHash $SourceHash
$StableHash = (Get-Sha256HexFromString -Value ($SourcePathValue + "|" + $Kind)).Substring(0, 10)
$CandidateRelativePath = "learn/candidates/learn-candidate-{0}-{1}.md" -f $Slug, $StableHash
$CandidatePath = Join-Path $Root ($CandidateRelativePath -replace '/', '\')

$QueueData = [pscustomobject]@{
  schema = "a-brain-dream-review-queue-v1"
  items = @()
}
if (Test-Path -LiteralPath $QueueFile) {
  $QueueData = Get-Content -LiteralPath $QueueFile -Raw | ConvertFrom-Json
}

$ReviewItems = @($QueueData.items)
$UsedReviewIds = @{}
foreach ($ReviewItem in $ReviewItems) {
  if ($null -ne $ReviewItem -and -not [string]::IsNullOrWhiteSpace([string]$ReviewItem.id)) {
    $UsedReviewIds[[string]$ReviewItem.id] = 1
  }
}

$ExistingReviewItem = $null
foreach ($ReviewItem in $ReviewItems) {
  $ReviewState = "pending_human_review"
  if ($ReviewItem.human_review -and $ReviewItem.human_review.state) {
    $ReviewState = [string]$ReviewItem.human_review.state
  }

  if (
    $ReviewItem.item_type -eq "learn_candidate" -and
    $ReviewState -eq "pending_human_review" -and
    (
      $ReviewItem.path -eq $CandidateRelativePath -or
      (
        $ReviewItem.source_path -eq $SourcePathValue -and
        $ReviewItem.kind -eq $Kind
      )
    )
  ) {
    $ExistingReviewItem = $ReviewItem
    break
  }
}

if ($null -ne $ExistingReviewItem -and -not [string]::IsNullOrWhiteSpace([string]$ExistingReviewItem.path)) {
  $CandidateRelativePath = [string]$ExistingReviewItem.path
  $CandidatePath = Join-Path $Root ($CandidateRelativePath -replace '/', '\')
}

$ReviewId = ""
if ($null -ne $ExistingReviewItem) {
  $ReviewId = [string]$ExistingReviewItem.id
} else {
  $ReviewIdBase = "review-{0}-learn-{1}-{2}" -f $Now.ToString("yyyyMMdd-HHmmss-fff"), $Slug, $StableHash
  $ReviewId = Get-UniqueStringValue -BaseValue $ReviewIdBase -UsedValues $UsedReviewIds
  $ExistingReviewItem = [pscustomobject]@{
    id = $ReviewId
    created_at = $CreatedAt
    item_type = "learn_candidate"
    path = $CandidateRelativePath
    priority = "medium"
    reason = @("learn_candidate", $InputType, $Kind, "needs_human_review")
    source_path = $SourcePathValue
    source_hash = $SourceHash
    input_type = $InputType
    kind = $Kind
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

$ExistingReviewItem | Add-Member -NotePropertyName path -NotePropertyValue $CandidateRelativePath -Force
$ExistingReviewItem | Add-Member -NotePropertyName priority -NotePropertyValue "medium" -Force
$ExistingReviewItem | Add-Member -NotePropertyName reason -NotePropertyValue @("learn_candidate", $InputType, $Kind, "needs_human_review") -Force
$ExistingReviewItem | Add-Member -NotePropertyName source_path -NotePropertyValue $SourcePathValue -Force
$ExistingReviewItem | Add-Member -NotePropertyName source_hash -NotePropertyValue $SourceHash -Force
$ExistingReviewItem | Add-Member -NotePropertyName input_type -NotePropertyValue $InputType -Force
$ExistingReviewItem | Add-Member -NotePropertyName kind -NotePropertyValue $Kind -Force
$ExistingReviewItem | Add-Member -NotePropertyName updated_at -NotePropertyValue $CreatedAt -Force
if ($null -eq $ExistingReviewItem.human_review) {
  $ExistingReviewItem | Add-Member -NotePropertyName human_review -NotePropertyValue ([pscustomobject]@{}) -Force
}
$ExistingReviewItem.human_review | Add-Member -NotePropertyName state -NotePropertyValue "pending_human_review" -Force
$ExistingReviewItem.human_review | Add-Member -NotePropertyName comment -NotePropertyValue "" -Force

$CandidateContent = New-CandidateContent `
  -TitleValue $InferredTitle `
  -SummaryValue $Summary `
  -UpdatedValue $UpdatedDate `
  -InputTypeValue $InputType `
  -KindValue $Kind `
  -SourcePathValue $SourcePathValue `
  -SourceHashValue $SourceHash `
  -SourceIdsValue $SourceIds `
  -SourceHashesValue $SourceHashes `
  -ReviewIdValue $ReviewId `
  -TitleInferenceValue $TitleInference `
  -HeadingValues $HeadingValues `
  -ExcerptValue $Excerpt

Ensure-ParentDirectory -Path $CandidatePath
Ensure-ParentDirectory -Path $QueueFile
Ensure-ParentDirectory -Path $StateFile
[System.IO.File]::WriteAllText($CandidatePath, $CandidateContent, (New-Object System.Text.UTF8Encoding($false)))

$QueueSchema = if ($QueueData.schema) { [string]$QueueData.schema } else { "a-brain-dream-review-queue-v1" }
$QueueOutput = [ordered]@{
  schema = $QueueSchema
  items = $ReviewItems
}
$StateOutput = [ordered]@{
  schema = "a-brain-dream-review-state-v1"
  updatedAt = $CreatedAt
  counts = (Get-ReviewStateCounts -Items $ReviewItems -AllowedStates $AllowedReviewStates)
}

[System.IO.File]::WriteAllText($QueueFile, ($QueueOutput | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($StateFile, ($StateOutput | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

Write-Output ("A-Brain learn-candidate: {0}" -f $CandidateRelativePath)
Write-Output ("review item: {0}" -f $ReviewId)
Write-Output ("source path: {0}" -f $SourcePathValue)
