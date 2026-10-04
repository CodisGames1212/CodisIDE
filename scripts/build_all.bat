@echo off
REM Unified build entrypoint for codis_serial (Windows + optional WSL/Docker Android)
REM Run from Developer PowerShell for VS 2022 (recommended) so MSVC dev tools are available.

setlocal enabledelayedexpansion

REM Determine repo root (this script is in repo\scripts)
set SCRIPT_DIR=%~dp0
set REPO_ROOT=%SCRIPT_DIR%..
for %%I in ("%REPO_ROOT%") do set REPO_ROOT=%%~fI

REM Initialize MSVC and Windows SDK paths when launched outside Developer Command Prompt.
if not defined VSCMD_VER (
  set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
  if exist "!VSWHERE!" (
    for /f "usebackq tokens=*" %%I in (`"!VSWHERE!" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_INSTALL=%%I"
  )
  if defined VS_INSTALL if exist "!VS_INSTALL!\Common7\Tools\VsDevCmd.bat" call "!VS_INSTALL!\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64
  if not defined VSCMD_VER (
    echo Visual Studio C++ build tools could not be initialized.
    goto fail
  )
)

if not defined GODOT_CPP_DIR (
  set GODOT_CPP_DIR=%REPO_ROOT%\addons\codis_serial\native\godot-cpp\build
)

if not defined ANDROID_NDK_ROOT (
  set ANDROID_NDK_ROOT=C:\Users\Admin\AppData\Local\Android\Sdk\ndk\27.2.12479018
)

echo Repo root: %REPO_ROOT%
echo GODOT_CPP_DIR: %GODOT_CPP_DIR%
echo ANDROID_NDK_ROOT: %ANDROID_NDK_ROOT%

REM Build embedded godot-cpp if present and not built
if not exist "%REPO_ROOT%\addons\codis_serial\native\godot-cpp\CMakeLists.txt" (
  echo Embedded godot-cpp not found; ensure GODOT_CPP_DIR points to a valid build.
  goto fail
)
echo godot-cpp will be generated and built with the native extension.

REM Build Windows native
echo Building codis_serial native for host...
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO_ROOT%\scripts\build_windows.ps1" || goto fail

REM Android uses the Windows-host NDK directly.
echo Building Android ARM64 and ARM32...
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO_ROOT%\scripts\build_android.ps1" || goto fail

REM Linux desktop build via WSL if available
where wsl >nul 2>&1
if %ERRORLEVEL%==0 (
  echo Building Linux x86_64 via WSL...
  for /f "usebackq tokens=*" %%P in (`wsl --distribution Ubuntu --exec wslpath -a "%REPO_ROOT%"`) do set "WSL_REPO=%%P"
  wsl --distribution Ubuntu --exec env "GODOTCPP_SOURCE_DIR=!WSL_REPO!/addons/codis_serial/native/godot-cpp" bash "!WSL_REPO!/scripts/build_local.sh" || goto fail
) else (
  echo WSL not found; Linux desktop build was skipped.
  goto fail
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO_ROOT%\scripts\package_artifacts.ps1" || goto fail

echo Windows, Linux, and Android builds finished. Artifacts are under:
echo   %REPO_ROOT%\addons\codis_serial\bin\windows
echo   %REPO_ROOT%\addons\codis_serial\bin\linux
echo   %REPO_ROOT%\addons\codis_serial\bin\android
endlocal
goto :eof

:fail
echo Build failed. Inspect output above.
exit /b 1
