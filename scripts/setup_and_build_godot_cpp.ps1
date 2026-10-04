# Builds embedded godot-cpp if needed (run from Developer PowerShell or MSYS2 shell as appropriate)
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
$embedDir = Join-Path $repoRoot "addons\codis_serial\native\godot-cpp"
$buildDir = Join-Path $embedDir "build"

if (-not (Test-Path $embedDir)) {
    Write-Error "Embedded godot-cpp not found at $embedDir"
    exit 1
}

Push-Location $embedDir
git submodule update --init --recursive

if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}

Write-Host "Attempting MSVC build. Please run this inside Developer PowerShell for VS 2022."
try {
    cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=Release
    cmake --build build --config Release -- /m
    $env:GODOT_CPP_DIR = (Get-Item -Path $buildDir).FullName
    Write-Host "godot-cpp built to: $env:GODOT_CPP_DIR"
    Pop-Location
    exit 0
} catch {
    Write-Warning "MSVC build failed; you can build with MSYS2/MinGW or run the script in MSYS2."
    Pop-Location
    exit 1
}
