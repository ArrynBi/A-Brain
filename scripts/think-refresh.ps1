param()

$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "think-sync.ps1")
& (Join-Path $PSScriptRoot "think-embed.ps1")
Write-Output "A-Brain think-refresh complete."
