param(
  [string]$Type = "",
  [string]$Since = "",
  [string]$Until = "",
  [int]$Limit = [int]::MaxValue,
  [string]$Contains = ""
)

$ErrorActionPreference = "Stop"

function Parse-EventTimestamp {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  return [DateTimeOffset]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Parse-FilterTimestamp {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value,
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  try {
    return [DateTimeOffset]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture)
  } catch {
    throw ("{0} must be a valid date/time value." -f $Name)
  }
}

$Root = Split-Path -Parent $PSScriptRoot
$EventFile = Join-Path $Root "diary/events/events.jsonl"
if (-not (Test-Path -LiteralPath $EventFile)) {
  Write-Output "A-Brain diary-query: no events."
  exit 0
}

$SinceValue = $null
if (-not [string]::IsNullOrWhiteSpace($Since)) {
  $SinceValue = Parse-FilterTimestamp -Value $Since -Name "Since"
}

$UntilValue = $null
if (-not [string]::IsNullOrWhiteSpace($Until)) {
  $UntilValue = Parse-FilterTimestamp -Value $Until -Name "Until"
}

if ($Limit -lt 1) {
  throw "Limit must be at least 1."
}

$ContainsLower = $Contains.ToLowerInvariant()
$Events = New-Object System.Collections.Generic.List[object]

foreach ($Line in Get-Content -LiteralPath $EventFile) {
  if ([string]::IsNullOrWhiteSpace($Line)) {
    continue
  }

  try {
    $Event = $Line | ConvertFrom-Json
  } catch {
    throw "Failed to parse events.jsonl."
  }

  $EventTime = Parse-EventTimestamp -Value $Event.timestamp

  if (-not [string]::IsNullOrWhiteSpace($Type) -and $Event.type -ne $Type) {
    continue
  }

  if ($null -ne $SinceValue -and $EventTime -lt $SinceValue) {
    continue
  }

  if ($null -ne $UntilValue -and $EventTime -gt $UntilValue) {
    continue
  }

  if (-not [string]::IsNullOrWhiteSpace($ContainsLower)) {
    $Haystack = (@(
        [string]$Event.id
        [string]$Event.type
        [string]$Event.summary
        [string]$Event.source
        (($Event.payload | ConvertTo-Json -Compress -Depth 100))
      ) -join "`n").ToLowerInvariant()

    if (-not $Haystack.Contains($ContainsLower)) {
      continue
    }
  }

  $Events.Add([pscustomobject]@{
      event = $Event
      timestamp = $EventTime
    })
}

$Selected = @($Events | Sort-Object -Property timestamp -Descending | Select-Object -First $Limit)
if ($Selected.Count -eq 0) {
  Write-Output "A-Brain diary-query: no events."
  exit 0
}

foreach ($Item in $Selected) {
  $Event = $Item.event
  $Summary = ([string]$Event.summary).Trim()
  if ([string]::IsNullOrWhiteSpace($Summary)) {
    $Summary = "-"
  }

  $PayloadJson = $Event.payload | ConvertTo-Json -Compress -Depth 100
  if ($PayloadJson.Length -gt 100) {
    $PayloadJson = $PayloadJson.Substring(0, 100) + "..."
  }

  Write-Output ("{0} [{1}] {2} ({3}) {4}" -f $Event.timestamp, $Event.type, $Summary, $Event.id, $PayloadJson)
}
