# Run full local build and capture detailed logs.
# Run this from "Developer PowerShell for VS 2022" as one command:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_full_build_and_log.ps1

$ErrorActionPreference = 'Stop'

# Populate MSVC and Windows SDK paths when not already in a Developer shell.
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

# Adjust if needed
$repoRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "..")
$repoRoot = $repoRoot.ProviderPath
$godotCppSrc = Join-Path $repoRoot "addons\codis_serial\native\godot-cpp"
$nativeSrc = Join-Path $repoRoot "addons\codis_serial\native"
$nativeBuild = Join-Path $nativeSrc "build"
$binDir = Join-Path $nativeSrc "..\bin\windows"
$log = Join-Path $repoRoot "build_full_log.txt"

# Environment defaults (override in session if needed)
if (-not $env:GODOT_CPP_DIR) { $env:GODOT_CPP_DIR = $godotCppSrc }
if (-not (Test-Path (Join-Path $env:GODOT_CPP_DIR "CMakeLists.txt"))) {
    $env:GODOT_CPP_DIR = Split-Path -Parent $env:GODOT_CPP_DIR
}
if (-not (Test-Path (Join-Path $env:GODOT_CPP_DIR "CMakeLists.txt"))) {
    throw "godot-cpp source tree was not found."
}
if (-not $env:ANDROID_NDK_ROOT) { $env:ANDROID_NDK_ROOT = "C:\Users\Admin\AppData\Local\Android\Sdk\ndk\27.2.12479018" }

"`n==== Build run at $(Get-Date) ====" | Out-File -FilePath $log -Encoding utf8

function RunAndLog($cmd, $desc) {
    "`n--- $desc ---" | Out-File -FilePath $log -Append
    "`$ $cmd" | Out-File -FilePath $log -Append
    try {
        Invoke-Expression $cmd 2>&1 | Tee-Object -FilePath $log -Append
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE."
        }
    } catch {
        "`nERROR during: $desc" | Out-File -FilePath $log -Append
        throw
    }
}

# Report tool availability
"Tools:" | Out-File -FilePath $log -Append
"cl: $(if (Get-Command cl -ErrorAction SilentlyContinue) { (Get-Command cl).Source } else { 'NOT FOUND' })" | Out-File -FilePath $log -Append
"cmake: $(if (Get-Command cmake -ErrorAction SilentlyContinue) { (Get-Command cmake).Source } else { 'NOT FOUND' })" | Out-File -FilePath $log -Append
"git: $(if (Get-Command git -ErrorAction SilentlyContinue) { (Get-Command git).Source } else { 'NOT FOUND' })" | Out-File -FilePath $log -Append

# Configure and build native codis_serial
RunAndLog "cmake -S `"$nativeSrc`" -B `"$nativeBuild`" -DGODOTCPP_SOURCE_DIR=`"$env:GODOT_CPP_DIR`" -G Ninja -DCMAKE_BUILD_TYPE=Release" "CMake configure codis_serial (MSVC)"
RunAndLog "cmake --build `"$nativeBuild`" --parallel" "Build codis_serial (MSVC)"

# Ensure bin dir and copy artifact(s)
if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir | Out-Null }
$artifacts = Get-ChildItem -Path $binDir -Filter "codis_serial.windows.template_release.dll" -ErrorAction SilentlyContinue
if ($null -eq $artifacts -or $artifacts.Count -eq 0) {
    "No Windows release artifact found in $binDir" | Out-File -FilePath $log -Append
} else {
    foreach ($a in $artifacts) {
        "Built artifact: $($a.FullName)" | Out-File -FilePath $log -Append
    }
}

# Final report
"`n==== Summary (end $(Get-Date)) ====" | Out-File -FilePath $log -Append
"Artifacts in $binDir:" | Out-File -FilePath $log -Append
Get-ChildItem -Path $binDir -Recurse -ErrorAction SilentlyContinue | Out-File -FilePath $log -Append

# Show top of log and path
Get-Content $log -TotalCount 200
Write-Host "`nFull build log saved to: $log"
