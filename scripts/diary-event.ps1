param(
  [string]$Type = "workflow_action",
  [string]$Summary = "",
  [string]$PayloadJson = "{}",
  [string]$PayloadJsonBase64 = ""
)

$ErrorActionPreference = "Stop"

$AllowedTypes = @(
  "task_start",
  "task_end",
  "workflow_action",
  "think_query",
  "note_written",
  "file_changed",
  "service_event",
  "review_decision"
)

function Test-IsJsonObject {
  param(
    [Parameter(Mandatory = $true)]
    [AllowNull()]
    [object]$Value
  )

  return ($Value -is [System.Management.Automation.PSCustomObject] -or
    $Value -is [System.Collections.IDictionary] -or
    $Value -is [hashtable])
}

if ($AllowedTypes -notcontains $Type) {
  throw ("Type must be one of: {0}" -f ($AllowedTypes -join ", "))
}

$Summary = $Summary.Trim()
if ([string]::IsNullOrWhiteSpace($Summary)) {
  throw "Summary is required for all diary events."
}

if (-not [string]::IsNullOrWhiteSpace($PayloadJsonBase64)) {
  try {
    $StrictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $PayloadJson = $StrictUtf8.GetString([System.Convert]::FromBase64String($PayloadJsonBase64))
  } catch {
    throw "PayloadJsonBase64 must be valid base64-encoded UTF-8 JSON."
  }
}

$PayloadJsonText = $PayloadJson.Trim()
if (-not $PayloadJsonText.StartsWith("{")) {
  throw "PayloadJson must be a JSON object."
}

try {
  $Payload = $PayloadJsonText | ConvertFrom-Json
} catch {
  throw "PayloadJson must be valid JSON."
}

if (-not (Test-IsJsonObject -Value $Payload)) {
  throw "PayloadJson must be a JSON object."
}

$Root = Split-Path -Parent $PSScriptRoot
$EventDir = Join-Path $Root "diary/events"
$EventFile = Join-Path $EventDir "events.jsonl"
New-Item -ItemType Directory -Force -Path $EventDir | Out-Null

$Now = Get-Date
$Event = [ordered]@{
  id = "evt_{0}_{1}" -f $Now.ToString("yyyyMMddHHmmssfff"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
  timestamp = $Now.ToString("o")
  type = $Type
  summary = $Summary
  actor = "agent"
  source = "diary-event"
  workspace = (Get-Location).Path
  payload = $Payload
}

($Event | ConvertTo-Json -Compress -Depth 100) | Add-Content -LiteralPath $EventFile -Encoding UTF8
Write-Output ("A-Brain diary event written: {0} [{1}]" -f $Event.id, $Event.type)
