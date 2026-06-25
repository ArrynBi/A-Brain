param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$IndexDir = Join-Path $Root "think/indexes"
$StateFile = Join-Path $IndexDir "sync-state.json"
New-Item -ItemType Directory -Force -Path $IndexDir | Out-Null

$SearchRoots = @("diary", "knowledge", "library") | ForEach-Object { Join-Path $Root $_ }
$Extensions = @(".md", ".json", ".jsonl", ".txt")
function Get-Sha256Hex {
  param([string]$Path)
  $Sha = [System.Security.Cryptography.SHA256]::Create()
  $Stream = [System.IO.File]::OpenRead($Path)
  try {
    $HashBytes = $Sha.ComputeHash($Stream)
    return -join ($HashBytes | ForEach-Object { $_.ToString("x2") })
  } finally {
    $Stream.Dispose()
    $Sha.Dispose()
  }
}

$Files = foreach ($SearchRoot in $SearchRoots) {
  if (Test-Path -LiteralPath $SearchRoot) {
    Get-ChildItem -LiteralPath $SearchRoot -Recurse -File |
      Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
      ForEach-Object {
        $Relative = $_.FullName.Substring($Root.Length).TrimStart("\")
        [ordered]@{
          path = $Relative.Replace("\", "/")
          bytes = $_.Length
          lastWriteTimeUtc = $_.LastWriteTimeUtc.ToString("o")
          sha256 = Get-Sha256Hex -Path $_.FullName
        }
      }
  }
}

$State = [ordered]@{
  schema = "a-brain-think-sync-state-v1"
  updatedAt = (Get-Date).ToString("o")
  fileCount = @($Files).Count
  files = @($Files)
}

$State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StateFile -Encoding UTF8
Write-Output "A-Brain think-sync complete: $($State.fileCount) files tracked."
