param([string]$Label = 'before-change')
$ErrorActionPreference = 'Stop'
$portalRoot = $PSScriptRoot
$backupDir = Join-Path $portalRoot 'backups'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$safeLabel = $Label -replace '[^a-zA-Z0-9-]', '-'
$destination = Join-Path $backupDir ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + $safeLabel + '.zip')
$items = @(Get-ChildItem -LiteralPath $portalRoot -Force | Where-Object {
    $_.Name -notin @('backups','releases','node_modules','.git','.vercel','data','coverage') -and
    ($_.Name -notlike '.env*' -or $_.Name -eq '.env.example') -and $_.Name -notlike '*.log'
})
if ($items.Count -gt 0) { Compress-Archive -LiteralPath $items.FullName -DestinationPath $destination }
Write-Output $destination
