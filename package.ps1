$ErrorActionPreference = 'Stop'
$portalRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$releaseDir = Join-Path $portalRoot 'releases'
New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
$destination = Join-Path $releaseDir ('APOC-Raid-Portal-0.2.0-foundation.1-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.zip')
$allowedFiles = @('package.json','.gitignore','.env.example','README.md','TEST-RESULTS.md','backup.ps1','package.ps1')
$allowedDirectories = @('api','src','scripts','tests','db','docs','backups')
$entries = @()
foreach ($name in $allowedFiles) { $entries += Get-Item -LiteralPath (Join-Path $portalRoot $name) }
foreach ($name in $allowedDirectories) { $entries += Get-ChildItem -LiteralPath (Join-Path $portalRoot $name) -Recurse -File }
Add-Type -AssemblyName System.IO.Compression
$stream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew)
$archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
try {
  foreach ($file in $entries) {
    $resolved = (Resolve-Path -LiteralPath $file.FullName).Path
    if (-not $resolved.StartsWith($portalRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Package entry outside project.' }
    $relative = $resolved.Substring($portalRoot.Length + 1).Replace('\','/')
    if ($relative -match '(^|/)(node_modules|data|\.git|\.vercel)(/|$)' -or
        ($file.Name -like '.env*' -and $file.Name -ne '.env.example')) { throw 'Unexpected private file in package.' }
    $entry = $archive.CreateEntry('APOC-Raid-Portal/' + $relative, [IO.Compression.CompressionLevel]::Optimal)
    $inputStream = [IO.File]::OpenRead($resolved)
    $outputStream = $entry.Open()
    try { $inputStream.CopyTo($outputStream) } finally { $inputStream.Dispose(); $outputStream.Dispose() }
  }
} finally { $archive.Dispose(); $stream.Dispose() }
Get-Item -LiteralPath $destination | Select-Object FullName,Length
Get-FileHash -LiteralPath $destination -Algorithm SHA256
