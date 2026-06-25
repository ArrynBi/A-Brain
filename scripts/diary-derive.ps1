param()

$ErrorActionPreference = "Stop"

function Parse-EventTimestamp {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  return [DateTimeOffset]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function New-TurnObject {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Id,
    [Parameter(Mandatory = $true)]
    [string]$Kind,
    [Parameter(Mandatory = $true)]
    [object[]]$Events
  )

  $FirstEvent = $Events[0]
  $LastEvent = $Events[$Events.Count - 1]
  $Summary = ([string]$FirstEvent.summary).Trim()
  if ([string]::IsNullOrWhiteSpace($Summary)) {
    $Summary = [string]$FirstEvent.type
  }

  return [ordered]@{
    id = $Id
    kind = $Kind
    start_time = $FirstEvent.timestamp
    end_time = $LastEvent.timestamp
    event_ids = @($Events | ForEach-Object { $_.id })
    summary = $Summary
  }
}

$Root = Split-Path -Parent $PSScriptRoot
$EventFile = Join-Path $Root "diary/events/events.jsonl"
$TurnsDir = Join-Path $Root "diary/turns"
$SessionsDir = Join-Path $Root "diary/sessions"
$TurnsFile = Join-Path $TurnsDir "turns.json"
$SessionsFile = Join-Path $SessionsDir "sessions.json"

New-Item -ItemType Directory -Force -Path $TurnsDir | Out-Null
New-Item -ItemType Directory -Force -Path $SessionsDir | Out-Null

$Events = @()
if (Test-Path -LiteralPath $EventFile) {
  $Events = @(foreach ($Line in Get-Content -LiteralPath $EventFile) {
      if ([string]::IsNullOrWhiteSpace($Line)) {
        continue
      }

      $Event = $Line | ConvertFrom-Json
      [pscustomobject]@{
        id = [string]$Event.id
        timestamp = [string]$Event.timestamp
        type = [string]$Event.type
        summary = [string]$Event.summary
        actor = [string]$Event.actor
        source = [string]$Event.source
        workspace = [string]$Event.workspace
        payload = $Event.payload
        parsed_time = Parse-EventTimestamp -Value $Event.timestamp
      }
    })
}

$Events = @($Events | Sort-Object -Property parsed_time, id)
$Turns = New-Object System.Collections.Generic.List[object]
$OpenTurnEvents = New-Object System.Collections.Generic.List[object]
$TurnCounter = 0

foreach ($Event in $Events) {
  if ($OpenTurnEvents.Count -gt 0) {
    $OpenTurnEvents.Add($Event) | Out-Null

    if ($Event.type -eq "task_end") {
      $TurnCounter++
      $Turns.Add((New-TurnObject -Id ("turn_{0:0000}" -f $TurnCounter) -Kind "task_turn" -Events $OpenTurnEvents.ToArray())) | Out-Null
      $OpenTurnEvents = New-Object System.Collections.Generic.List[object]
    }

    continue
  }

  if ($Event.type -eq "task_start") {
    $OpenTurnEvents.Add($Event) | Out-Null
    continue
  }

  $TurnCounter++
  $Turns.Add((New-TurnObject -Id ("turn_{0:0000}" -f $TurnCounter) -Kind "auto_turn" -Events @($Event))) | Out-Null
}

if ($OpenTurnEvents.Count -gt 0) {
  $TurnCounter++
  $Turns.Add((New-TurnObject -Id ("turn_{0:0000}" -f $TurnCounter) -Kind "task_turn" -Events $OpenTurnEvents.ToArray())) | Out-Null
}

$TurnArray = @($Turns.ToArray())
$SessionArray = @()

if ($Events.Count -gt 0) {
  $FirstEvent = $Events[0]
  $LastEvent = $Events[$Events.Count - 1]
  $SessionArray = @([ordered]@{
      id = "session_0001"
      kind = "batch_session"
      start_time = $FirstEvent.timestamp
      end_time = $LastEvent.timestamp
      event_ids = @($Events | ForEach-Object { $_.id })
      turn_ids = @($TurnArray | ForEach-Object { $_.id })
      summary = ("Batch session derived from {0} events and {1} turns." -f $Events.Count, $TurnArray.Count)
    })
}

Set-Content -LiteralPath $TurnsFile -Encoding UTF8 -Value (ConvertTo-Json -InputObject $TurnArray -Depth 100)
Set-Content -LiteralPath $SessionsFile -Encoding UTF8 -Value (ConvertTo-Json -InputObject $SessionArray -Depth 100)

Write-Output ("A-Brain diary derive complete: {0} turns, {1} sessions." -f $TurnArray.Count, $SessionArray.Count)
