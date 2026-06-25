param(
  [switch]$Queue,
  [switch]$Report,
  [string]$Priority = "",
  [string]$Item = "",
  [string]$Decision = "",
  [string]$Comment = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$QueueFile = Join-Path $Root "dream/review/queue.json"
$StateFile = Join-Path $Root "dream/review/state.json"
$ReportDir = Join-Path $Root "dream/review/reports"

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

$ConfigFile = Join-Path $Root "config/a-brain.json"
if (Test-Path -LiteralPath $ConfigFile) {
  $Config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
  if ($Config.dream.reviewStates) {
    $AllowedReviewStates = @($Config.dream.reviewStates)
  }
}

if ($Decision -and ($AllowedReviewStates -notcontains $Decision)) {
  throw "Invalid review decision '$Decision'. Allowed values: $($AllowedReviewStates -join ', ')"
}
if ($Decision -and -not $Item) {
  throw "A review decision requires -Item."
}
if ($Item -and -not $Decision) {
  throw "A review item update requires -Decision."
}

New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

if (-not (Test-Path -LiteralPath $QueueFile)) {
  @{ schema = "a-brain-dream-review-queue-v1"; items = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $QueueFile -Encoding UTF8
}

$QueueData = Get-Content -LiteralPath $QueueFile -Raw | ConvertFrom-Json
$Items = @($QueueData.items)

if ($Item -and $Decision) {
  $Found = $false
  foreach ($ReviewItem in $Items) {
    if ($ReviewItem.id -eq $Item) {
      $Found = $true
      if ($null -eq $ReviewItem.human_review) {
        $ReviewItem | Add-Member -NotePropertyName human_review -NotePropertyValue ([pscustomobject]@{}) -Force
      }
      $ReviewItem.human_review | Add-Member -NotePropertyName state -NotePropertyValue $Decision -Force
      $ReviewItem.human_review | Add-Member -NotePropertyName reviewed_at -NotePropertyValue (Get-Date).ToString("o") -Force
      $ReviewItem.human_review | Add-Member -NotePropertyName comment -NotePropertyValue $Comment -Force
    }
  }
  if (-not $Found) { throw "Review item not found: $Item" }
  [ordered]@{ schema = $QueueData.schema; items = $Items } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $QueueFile -Encoding UTF8
  & (Join-Path $PSScriptRoot "diary-event.ps1") -Type "review_decision" -Summary "dream-review $Item -> $Decision" -PayloadJson (@{ item = $Item; decision = $Decision; comment = $Comment } | ConvertTo-Json -Compress) | Out-Null
}

$Counts = [ordered]@{}
foreach ($AllowedState in $AllowedReviewStates) {
  $Counts[$AllowedState] = 0
}
foreach ($ReviewItem in $Items) {
  $State = "pending_human_review"
  if ($ReviewItem.human_review -and $ReviewItem.human_review.state) { $State = $ReviewItem.human_review.state }
  if ($AllowedReviewStates -notcontains $State) { $State = "pending_human_review" }
  if (-not $Counts.Contains($State)) { $Counts[$State] = 0 }
  $Counts[$State] += 1
}

$StateData = [ordered]@{
  schema = "a-brain-dream-review-state-v1"
  updatedAt = (Get-Date).ToString("o")
  counts = $Counts
}
$StateData | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StateFile -Encoding UTF8

$Filtered = $Items
if ($Priority) {
  $Filtered = @($Items | Where-Object { $_.priority -eq $Priority })
}

$ReportFile = Join-Path $ReportDir ("review-report-{0}.md" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))
$Lines = @(
  "# A-Brain Dream Review Report",
  "",
  "- Generated: $((Get-Date).ToString("o"))",
  "- Queue: dream/review/queue.json",
  "- Items: $($Filtered.Count)",
  "",
  "## Counts",
  ""
)
foreach ($Key in $Counts.Keys) {
  $Lines += "- ${Key}: $($Counts[$Key])"
}
$Lines += ""
$Lines += "## Items"
$Lines += ""
if ($Filtered.Count -eq 0) {
  $Lines += "No review items."
} else {
  foreach ($ReviewItem in $Filtered) {
    $Lines += "- `$($ReviewItem.id)` $($ReviewItem.item_type) $($ReviewItem.path) [$($ReviewItem.priority)]"
  }
}
$Lines | Set-Content -LiteralPath $ReportFile -Encoding UTF8

Write-Output "A-Brain dream-review report: $ReportFile"
if ($Filtered.Count -eq 0) {
  Write-Output "No review items."
} else {
  foreach ($ReviewItem in $Filtered) {
    Write-Output ("{0} {1} {2}" -f $ReviewItem.id, $ReviewItem.priority, $ReviewItem.path)
  }
}
