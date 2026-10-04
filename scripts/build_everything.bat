@echo off
REM Unified build: configure+build godot-cpp (embedded) and codis_serial native (host).
setlocal enabledelayedexpansion

REM Initialize MSVC and Windows SDK paths when launched outside Developer Command Prompt.
if not defined VSCMD_VER (
  set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
  if exist "!VSWHERE!" (
    for /f "usebackq tokens=*" %%I in (`"!VSWHERE!" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_INSTALL=%%I"
  )
  if defined VS_INSTALL if exist "!VS_INSTALL!\Common7\Tools\VsDevCmd.bat" call "!VS_INSTALL!\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64
  if not defined VSCMD_VER (
    echo Visual Studio C++ build tools could not be initialized.
    exit /b 1
  )
)

REM repo root
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "REPO_ROOT=%%~fI"

REM defaults (override by env)
if not defined GODOT_CPP_DIR set "GODOT_CPP_DIR=%REPO_ROOT%\addons\codis_serial\native\godot-cpp\build"
if not defined ANDROID_NDK_ROOT set "ANDROID_NDK_ROOT=C:\Users\Admin\AppData\Local\Android\Sdk\ndk\27.2.12479018"

echo Repo root: %REPO_ROOT%
echo GODOT_CPP_DIR: %GODOT_CPP_DIR%
echo ANDROID_NDK_ROOT: %ANDROID_NDK_ROOT%
echo =====================================================

REM Build embedded godot-cpp if present
set "EMBED_GODOT_CPP=%REPO_ROOT%\addons\codis_serial\native\godot-cpp"
if exist "%EMBED_GODOT_CPP%" (
  echo godot-cpp will be generated and built with the native extension.
)

REM Build host native
where cl >nul 2>&1
if %ERRORLEVEL%==0 (
  cmake -S "%REPO_ROOT%\addons\codis_serial\native" -B "%REPO_ROOT%\addons\codis_serial\native\build" -DGODOTCPP_SOURCE_DIR="%EMBED_GODOT_CPP%" -G Ninja -DCMAKE_BUILD_TYPE=Release || goto cmake_fail
  cmake --build "%REPO_ROOT%\addons\codis_serial\native\build" --parallel || goto build_fail
  if exist "%REPO_ROOT%\addons\codis_serial\bin\windows\codis_serial.windows.template_release.dll" (
    echo Built %REPO_ROOT%\addons\codis_serial\bin\windows\codis_serial.windows.template_release.dll
  ) else (
    goto fail
  )
) else (
  goto fail
)

REM Android uses the Windows-host NDK.
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO_ROOT%\scripts\build_android.ps1" || goto build_fail

REM Linux desktop build via WSL (if installed)
where wsl >nul 2>&1
if %ERRORLEVEL%==0 (
  for /f "usebackq tokens=*" %%P in (`wsl --distribution Ubuntu --exec wslpath -a "%REPO_ROOT%"`) do set "WSL_REPO=%%P"
  wsl --distribution Ubuntu --exec env "GODOTCPP_SOURCE_DIR=!WSL_REPO!/addons/codis_serial/native/godot-cpp" bash "!WSL_REPO!/scripts/build_local.sh" || goto build_fail
) else (
  call :fail "WSL is required to build the Linux desktop library."
)

echo Windows, Linux, and Android build finished. Check:
echo   %REPO_ROOT%\addons\codis_serial\bin
exit /b 0

:cmake_fail
echo CMake configure failed.
exit /b 1

:build_fail
echo Build failed.
exit /b 1

:fail
echo Build failed. Check the errors above.
exit /b 1
