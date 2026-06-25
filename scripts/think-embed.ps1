param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$IndexDir = Join-Path $Root "think/indexes"
$TextIndexFile = Join-Path $IndexDir "text-index.json"
New-Item -ItemType Directory -Force -Path $IndexDir | Out-Null

$SearchRoots = @("diary", "knowledge", "library") | ForEach-Object { Join-Path $Root $_ }
$Extensions = @(".md", ".json", ".jsonl", ".txt")
function Read-TextFile {
  param([string]$Path)
  try {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
  } catch {
    return [System.IO.File]::ReadAllText($Path)
  }
}

$Entries = foreach ($SearchRoot in $SearchRoots) {
  if (Test-Path -LiteralPath $SearchRoot) {
    Get-ChildItem -LiteralPath $SearchRoot -Recurse -File |
      Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
      ForEach-Object {
        $Text = Read-TextFile -Path $_.FullName
        if ($null -eq $Text) { $Text = "" }
        $Relative = $_.FullName.Substring($Root.Length).TrimStart("\").Replace("\", "/")
        $Snippet = $Text
        if ($Snippet.Length -gt 500) { $Snippet = $Snippet.Substring(0, 500) }
        [ordered]@{
          path = $Relative
          title = [IO.Path]::GetFileNameWithoutExtension($_.Name)
          chars = $Text.Length
          snippet = $Snippet
        }
      }
  }
}

$Index = [ordered]@{
  schema = "a-brain-local-text-index-v1"
  mode = "local-text"
  note = "This is a lightweight text index, not a semantic embedding index."
  updatedAt = (Get-Date).ToString("o")
  entryCount = @($Entries).Count
  entries = @($Entries)
}

$Index | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $TextIndexFile -Encoding UTF8
Write-Output "A-Brain think-embed complete: local-text index has $($Index.entryCount) entries."
