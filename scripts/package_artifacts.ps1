$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).ProviderPath
$binaryRoot = Join-Path $repoRoot 'addons\codis_serial\bin'
$distDir = Join-Path $repoRoot 'dist'
$archive = Join-Path $distDir 'codis_serial_artifacts.zip'

$artifacts = Get-ChildItem $binaryRoot -Recurse -File | Where-Object {
    $_.Extension -in @('.dll', '.so', '.dylib')
}
if (-not $artifacts) {
    throw "No GDExtension binaries found under $binaryRoot."
}

New-Item -ItemType Directory -Path $distDir -Force | Out-Null
if (Test-Path $archive) { Remove-Item $archive -Force }
Compress-Archive -Path (Join-Path $binaryRoot '*') -DestinationPath $archive -CompressionLevel Optimal

Write-Host "Packaged $($artifacts.Count) extension binaries: $archive"
