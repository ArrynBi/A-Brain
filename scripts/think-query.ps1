param(
  [ValidateSet("brief", "normal", "deep", "auto")]
  [string]$Mode = "auto",

  [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$QueryParts
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$IndexFile = Join-Path $Root "think/indexes/text-index.json"
$Query = ($QueryParts -join " ").Trim()

if ([string]::IsNullOrWhiteSpace($Query)) {
  throw "Usage: think-query.cmd [-Mode brief|normal|deep|auto] ""<query>"""
}

function Get-LayerFromPath {
  param([string]$Path)

  $Normalized = ($Path -replace "\\", "/").ToLowerInvariant()
  if ($Normalized.StartsWith("knowledge/processes/")) { return "process" }
  if ($Normalized.StartsWith("knowledge/concepts/")) { return "concept" }
  if ($Normalized.StartsWith("knowledge/projects/")) { return "project" }
  if ($Normalized.StartsWith("knowledge/notes/")) { return "note" }
  if ($Normalized.StartsWith("diary/sessions/")) { return "diary_session" }
  if ($Normalized.StartsWith("diary/turns/")) { return "diary_turn" }
  if ($Normalized.StartsWith("diary/events/")) { return "diary_event" }
  if ($Normalized.StartsWith("library/")) { return "library" }
  return "other"
}

function Test-AnyPattern {
  param(
    [string]$Text,
    [string[]]$Patterns
  )

  foreach ($Pattern in $Patterns) {
    if ($Text -match $Pattern) { return $true }
  }
  return $false
}

function Get-IntentProfile {
  param([string]$RawQuery)

  $Lower = $RawQuery.ToLowerInvariant()
  $Profile = [ordered]@{
    intent = "general"
    layers = @("note", "concept", "process", "project", "diary_session", "library", "diary_turn", "diary_event", "other")
    exactLean = $false
    analysisLean = $false
  }

  if (Test-AnyPattern -Text $RawQuery -Patterns @("怎么", "如何", "流程", "步骤", "操作", "(?i)\bprocess\b")) {
    $Profile.intent = "process"
    $Profile.layers = @("process", "note", "concept", "project", "diary_session", "library", "diary_turn", "diary_event", "other")
  } elseif (Test-AnyPattern -Text $RawQuery -Patterns @("是什么", "为什么", "原则", "概念", "定义", "(?i)\bconcept\b")) {
    $Profile.intent = "concept"
    $Profile.layers = @("concept", "note", "process", "project", "library", "diary_session", "diary_turn", "diary_event", "other")
  } elseif (Test-AnyPattern -Text $RawQuery -Patterns @("项目", "状态", "进展", "(?i)\bproject\b")) {
    $Profile.intent = "project"
    $Profile.layers = @("project", "diary_session", "note", "process", "concept", "diary_turn", "diary_event", "library", "other")
  } elseif (Test-AnyPattern -Text $RawQuery -Patterns @("最近", "上次", "昨天", "今天", "时间", "做过", "(?i)\bsession\b", "(?i)\bturn\b", "(?i)\bdiary\b")) {
    $Profile.intent = "diary"
    $Profile.layers = @("diary_session", "diary_turn", "diary_event", "note", "project", "process", "concept", "library", "other")
  } elseif (Test-AnyPattern -Text $RawQuery -Patterns @("证据", "来源", "引用", "(?i)\bsource\b", "(?i)\blibrary\b", "原文")) {
    $Profile.intent = "source"
    $Profile.layers = @("library", "note", "concept", "process", "project", "diary_session", "diary_turn", "diary_event", "other")
  }

  if (Test-AnyPattern -Text $RawQuery -Patterns @("分析", "设计", "架构", "审查", "计划")) {
    $Profile.analysisLean = $true
  }

  if (Test-AnyPattern -Text $RawQuery -Patterns @("[\\/]", "\.[A-Za-z0-9]{1,8}\b", "::", "--", "\$", "(?i)\b[a-z0-9_-]+\.(ps1|cmd|md|json|jsonl|txt)\b")) {
    $Profile.exactLean = $true
  }

  return [pscustomobject]$Profile
}

function Get-LayerBonus {
  param(
    [string]$Layer,
    [string[]]$PriorityLayers
  )

  for ($i = 0; $i -lt $PriorityLayers.Count; $i++) {
    if ($PriorityLayers[$i] -eq $Layer) {
      switch ($i) {
        0 { return 4 }
        1 { return 3 }
        2 { return 2 }
        3 { return 1 }
        default { return 0 }
      }
    }
  }
  return 0
}

function Get-TrimmedSnippet {
  param(
    [string]$Snippet,
    [int]$MaxLength = 180
  )

  if ($null -eq $Snippet) { return "" }
  $Text = ($Snippet -replace "\s+", " ").Trim()
  if ($Text.Length -le $MaxLength) { return $Text }
  return $Text.Substring(0, $MaxLength) + "..."
}

function Select-EffectiveMode {
  param(
    [string]$RequestedMode,
    [object[]]$Results,
    [object]$IntentProfile
  )

  $TopScore = 0
  $StrongHits = @()
  $StrongLayers = @()
  $LowConfidenceThreshold = 4
  $LowConfidence = $false
  $EffectiveMode = $RequestedMode
  $Reason = "requested"

  if ($Results.Count -gt 0) {
    $TopScore = $Results[0].score
    $StrongHits = @($Results | Where-Object { $_.score -ge [Math]::Max(4, $TopScore - 1) })
    $StrongLayers = @($StrongHits | Select-Object -ExpandProperty layer -Unique)
    if ($TopScore -lt $LowConfidenceThreshold) {
      $LowConfidence = $true
    }
  }

  if ($RequestedMode -eq "auto") {
    if ($Results.Count -eq 0) {
      $EffectiveMode = "normal"
      $Reason = "no_results"
    } elseif ($LowConfidence) {
      $EffectiveMode = "deep"
      $Reason = "low_confidence"
    } elseif ($IntentProfile.analysisLean) {
      if ($StrongLayers.Count -ge 3 -or $Results.Count -ge 8) {
        $EffectiveMode = "deep"
        $Reason = "analysis_or_broad"
      } else {
        $EffectiveMode = "normal"
        $Reason = "analysis_normal"
      }
    } elseif ($StrongHits.Count -ge 1 -and $StrongLayers.Count -le 1 -and $TopScore -ge 7) {
      $EffectiveMode = "brief"
      $Reason = "strong_focus"
    } elseif ($StrongLayers.Count -ge 3 -or $Results.Count -ge 8) {
      $EffectiveMode = "deep"
      $Reason = "broad_results"
    } else {
      $EffectiveMode = "normal"
      $Reason = "balanced"
    }
  }

  return [pscustomobject]@{
    effectiveMode = $EffectiveMode
    topScore = $TopScore
    strongHitCount = $StrongHits.Count
    strongLayers = $StrongLayers.Count
    analysisLean = [bool]$IntentProfile.analysisLean
    lowConfidence = $LowConfidence
    lowConfidenceThreshold = $LowConfidenceThreshold
    reason = $Reason
  }
}

function Write-ResultHeader {
  param(
    [string]$QueryText,
    [string]$RequestedMode,
    [string]$EffectiveMode,
    [object]$IntentProfile,
    [int]$ResultCount,
    [object]$RoutingDecision
  )

  Write-Output ("A-Brain think-query: {0}" -f $QueryText)
  Write-Output ("requested mode: {0}" -f $RequestedMode)
  Write-Output ("effective mode: {0}" -f $EffectiveMode)
  Write-Output ("intent: {0}{1}" -f $IntentProfile.intent, $(if ($IntentProfile.exactLean) { " | exact-lean" } else { "" }))
  Write-Output ("routing: topScore={0} strongHits={1} strongLayers={2} analysisLean={3} lowConfidence={4} threshold={5} reason={6}" -f $RoutingDecision.topScore, $RoutingDecision.strongHitCount, $RoutingDecision.strongLayers, $RoutingDecision.analysisLean.ToString().ToLowerInvariant(), $RoutingDecision.lowConfidence.ToString().ToLowerInvariant(), $RoutingDecision.lowConfidenceThreshold, $RoutingDecision.reason)
  Write-Output ("results: {0}" -f $ResultCount)
}

if (-not (Test-Path -LiteralPath $IndexFile)) {
  & (Join-Path $PSScriptRoot "think-embed.ps1") | Out-Null
}

if (-not (Test-Path -LiteralPath $IndexFile)) {
  throw "Index not found: $IndexFile"
}

$Index = Get-Content -LiteralPath $IndexFile -Raw | ConvertFrom-Json
$QueryLower = $Query.ToLowerInvariant()
$Terms = @($QueryLower.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries))
if ($Terms.Count -eq 0) { $Terms = @($QueryLower) }
$IntentProfile = Get-IntentProfile -RawQuery $Query

$Results = foreach ($Entry in $Index.entries) {
  $Layer = Get-LayerFromPath -Path $Entry.path
  $Haystack = (($Entry.path + "`n" + $Entry.title + "`n" + $Entry.snippet).ToLowerInvariant())
  $ExactScore = 0
  $TermScore = 0

  if ($Haystack.Contains($QueryLower)) { $ExactScore = 5 }
  foreach ($Term in $Terms) {
    if ($Term.Length -gt 0 -and $Haystack.Contains($Term)) { $TermScore += 1 }
  }

  $TextScore = $ExactScore + $TermScore
  $LayerBonus = Get-LayerBonus -Layer $Layer -PriorityLayers $IntentProfile.layers
  $Score = $TextScore + $LayerBonus

  if ($TextScore -gt 0) {
    [pscustomobject]@{
      score = $Score
      path = $Entry.path
      title = $Entry.title
      layer = $Layer
      snippet = (($Entry.snippet -replace "\s+", " ").Trim())
      breakdown = [ordered]@{
        exact = $ExactScore
        terms = $TermScore
        layerBonus = $LayerBonus
      }
    }
  }
}

$SortedResults = @(
  $Results |
    Sort-Object -Property @{ Expression = "score"; Descending = $true }, @{ Expression = "layer"; Descending = $false }, @{ Expression = "path"; Descending = $false }
)

$RoutingDecision = Select-EffectiveMode -RequestedMode $Mode -Results $SortedResults -IntentProfile $IntentProfile
$EffectiveMode = $RoutingDecision.effectiveMode
$Limit = 8
switch ($EffectiveMode) {
  "brief" { $Limit = 5 }
  "normal" { $Limit = 8 }
  "deep" { $Limit = 12 }
}

$Top = @($SortedResults | Select-Object -First $Limit)
Write-ResultHeader -QueryText $Query -RequestedMode $Mode -EffectiveMode $EffectiveMode -IntentProfile $IntentProfile -ResultCount $Top.Count -RoutingDecision $RoutingDecision

if ($Top.Count -eq 0) {
  Write-Output "未找到本地 A-Brain 命中。可以先补知识、运行 think-embed，或改写查询词后再试。"
  exit 0
}

if ($Mode -eq "auto" -and $EffectiveMode -eq "brief") {
  Write-Output "auto routing: 强命中集中，采用 brief 输出。"
} elseif ($Mode -eq "auto" -and $EffectiveMode -eq "deep") {
  if ($RoutingDecision.reason -eq "low_confidence") {
    Write-Output "auto routing: 有候选但 top score 偏低，按 low-confidence 分支采用 deep 输出。"
  } else {
    Write-Output "auto routing: 命中跨多层或问题偏分析，采用 deep 输出。"
  }
} elseif ($Mode -eq "auto") {
  Write-Output "auto routing: 采用 normal 输出。"
}

if ($EffectiveMode -eq "brief") {
  foreach ($Item in $Top) {
    Write-Output ("- layer={0} score={1} path={2} snippet={3}" -f $Item.layer, $Item.score, $Item.path, (Get-TrimmedSnippet -Snippet $Item.snippet -MaxLength 140))
  }
  exit 0
}

$Groups = $Top | Group-Object -Property layer
foreach ($Group in $Groups) {
  Write-Output ""
  Write-Output ("[{0}]" -f $Group.Name)
  foreach ($Item in $Group.Group) {
    Write-Output ("- score={0} path={1}" -f $Item.score, $Item.path)
    Write-Output ("  snippet: {0}" -f (Get-TrimmedSnippet -Snippet $Item.snippet -MaxLength $(if ($EffectiveMode -eq "deep") { 220 } else { 160 })))
    if ($EffectiveMode -eq "deep") {
      Write-Output ("  reason: exact={0} terms={1} layerBonus={2}" -f $Item.breakdown.exact, $Item.breakdown.terms, $Item.breakdown.layerBonus)
    }
  }
}
