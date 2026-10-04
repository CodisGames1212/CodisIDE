# Build script for Windows (MSVC). Run from Developer PowerShell for VS 2022.
$ErrorActionPreference = 'Stop'

# Initialize MSVC and Windows SDK library paths when this script is launched
# outside a Developer PowerShell prompt.
if (-not $env:VSCMD_VER) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsInstall = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        $vsDevCmd = Join-Path $vsInstall "Common7\Tools\VsDevCmd.bat"
        if (Test-Path $vsDevCmd) {
            $devEnvironment = & $env:ComSpec /d /s /c "`"$vsDevCmd`" -no_logo -arch=x64 -host_arch=x64 >nul && set"
            foreach ($entry in $devEnvironment) {
                if ($entry -match '^([^=]+)=(.*)$') {
                    [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
                }
            }
        }
    }
}

if (-not $env:VSCMD_VER) {
    throw "Visual Studio C++ build tools were not found. Install the MSVC x64/x86 build tools and Windows SDK."
}

# Resolve repo root relative to this script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
$repoRoot = $repoRoot.ProviderPath
$src = Join-Path $repoRoot "addons\codis_serial\native"
if (-not $env:GODOT_CPP_DIR) {
    $env:GODOT_CPP_DIR = Join-Path $src "godot-cpp"
}

Write-Host "Repo root: $repoRoot"
Write-Host "Native source: $src"
Write-Host "GODOT_CPP_DIR = $env:GODOT_CPP_DIR"

if (-not (Test-Path $src)) {
    Write-Error "Native source folder not found: $src"
    exit 1
}

$godotCppSource = $env:GODOT_CPP_DIR
if (-not (Test-Path (Join-Path $godotCppSource "CMakeLists.txt"))) {
    $godotCppSource = Split-Path -Parent $godotCppSource
}
if (-not (Test-Path (Join-Path $godotCppSource "CMakeLists.txt"))) {
    throw "godot-cpp source tree was not found at $env:GODOT_CPP_DIR."
}

foreach ($target in @('template_debug', 'template_release')) {
    $build = if ($target -eq 'template_release') { Join-Path $src 'build' } else { Join-Path $src "build-$target" }
    $buildType = if ($target -eq 'template_debug') { 'Debug' } else { 'Release' }
    Write-Host "Configuring CMake (Ninja + MSVC, $target)..."
    cmake -S $src -B $build "-DGODOTCPP_SOURCE_DIR=$godotCppSource" "-DGODOTCPP_TARGET=$target" -G Ninja "-DCMAKE_BUILD_TYPE=$buildType"
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed for $target with exit code $LASTEXITCODE."
    }

    Write-Host "Building ($target)..."
    cmake --build $build --parallel
    if ($LASTEXITCODE -ne 0) {
        throw "Native $target build failed with exit code $LASTEXITCODE."
    }

    $artifact = Join-Path $src "..\bin\windows\codis_serial.windows.$target.dll"
    if (-not (Test-Path $artifact)) {
        throw "Build completed but the GDExtension DLL was not produced at $artifact."
    }
    Write-Host "Windows build finished: $artifact"
}
