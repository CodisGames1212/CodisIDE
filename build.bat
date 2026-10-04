@echo off
setlocal EnableExtensions EnableDelayedExpansion
title CMake Build Helper

echo.
echo ============================================================
echo                    CMAKE BUILD HELPER
echo ============================================================
echo.

where cmake >nul 2>&1
if errorlevel 1 (
    echo ERROR: CMake was not found in PATH.
    echo.
    pause
    exit /b 1
)

:menu
echo.
echo Select platform:
echo.
echo   1 - Windows
echo   2 - Android
echo   3 - Linux
echo   4 - macOS
echo   5 - iOS
echo   6 - Emscripten
echo   7 - WSL
echo   8 - Custom
echo.

set "choice="
set /p "choice=Platform: "

if "%choice%"=="1" goto PLATFORM_WINDOWS
if "%choice%"=="2" goto PLATFORM_ANDROID
if "%choice%"=="3" goto PLATFORM_LINUX
if "%choice%"=="4" goto PLATFORM_MACOS
if "%choice%"=="5" goto PLATFORM_IOS
if "%choice%"=="6" goto PLATFORM_EMSCRIPTEN
if "%choice%"=="7" goto PLATFORM_WSL
if "%choice%"=="8" goto PLATFORM_CUSTOM

echo.
echo Invalid platform.
timeout /t 2 >nul
cls
goto menu


:PLATFORM_WINDOWS

set "PLATFORM=windows"
set "GENERATOR=Visual Studio 17 2022"
set "ARCH=x64"
set "MULTI=1"
set "TOOLCHAIN="

goto START_BUILD


:PLATFORM_ANDROID

set "PLATFORM=android"
set "GENERATOR=Ninja"
set "ARCH=arm64-v8a"
set "MULTI=0"

if defined ANDROID_NDK_HOME (
    set "NDK=%ANDROID_NDK_HOME%"
) else if defined ANDROID_NDK (
    set "NDK=%ANDROID_NDK%"
) else (
    echo.
    echo ERROR: ANDROID_NDK_HOME or ANDROID_NDK is not defined.
    echo.
    pause
    exit /b 1
)

set "TOOLCHAIN=-DCMAKE_TOOLCHAIN_FILE=%NDK%/build/cmake/android.toolchain.cmake -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-21"

goto START_BUILD


:PLATFORM_LINUX

set "PLATFORM=linux"
set "GENERATOR=Ninja"
set "ARCH=generic"
set "MULTI=0"
set "TOOLCHAIN="

goto START_BUILD


:PLATFORM_MACOS

set "PLATFORM=macos"
set "GENERATOR=Ninja"
set "ARCH=generic"
set "MULTI=0"
set "TOOLCHAIN="

if defined OSX_TOOLCHAIN (
    set "TOOLCHAIN=-DCMAKE_TOOLCHAIN_FILE=%OSX_TOOLCHAIN%"
)

goto START_BUILD


:PLATFORM_IOS

set "PLATFORM=ios"
set "GENERATOR=Ninja"
set "ARCH=generic"
set "MULTI=0"
set "TOOLCHAIN="

if defined IOS_TOOLCHAIN (
    set "TOOLCHAIN=-DCMAKE_TOOLCHAIN_FILE=%IOS_TOOLCHAIN%"
)

goto START_BUILD


:PLATFORM_EMSCRIPTEN

set "PLATFORM=emscripten"
set "GENERATOR=Ninja"
set "ARCH=generic"
set "MULTI=0"

if not defined EMSDK (
    echo.
    echo ERROR: EMSDK environment variable is not defined.
    echo.
    pause
    exit /b 1
)

set "TOOLCHAIN=-DCMAKE_TOOLCHAIN_FILE=%EMSDK%/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake"

goto START_BUILD


:PLATFORM_WSL

echo.
echo ============================================================
echo                         WSL BUILD
echo ============================================================
echo.

if not defined BUILD_TYPE set "BUILD_TYPE=Release"

wsl -e bash -lc "mkdir -p build && cd build && cmake .. -DCMAKE_BUILD_TYPE=%BUILD_TYPE% && cmake --build . --parallel"

set "RESULT=%ERRORLEVEL%"

echo.

if "%RESULT%"=="0" (
    echo WSL BUILD SUCCESSFUL.

    if exist "build" (
        start "" explorer.exe "%CD%\build"
    )
) else (
    echo WSL BUILD FAILED.
)

echo.
echo Press any key to close...
pause >nul

endlocal
exit /b %RESULT%


:PLATFORM_CUSTOM

set "PLATFORM=custom"

if defined CMAKE_GENERATOR (
    set "GENERATOR=%CMAKE_GENERATOR%"
) else (
    set "GENERATOR=Ninja"
)

set "ARCH=generic"
set "MULTI=0"
set "TOOLCHAIN="

if defined CMAKE_TOOLCHAIN_FILE (
    set "TOOLCHAIN=-DCMAKE_TOOLCHAIN_FILE=%CMAKE_TOOLCHAIN_FILE%"
)

goto START_BUILD


:START_BUILD

if not defined BUILD_TYPE set "BUILD_TYPE=Release"

echo.
echo ============================================================
echo                       BUILD SETTINGS
echo ============================================================
echo.
echo Platform    : %PLATFORM%
echo Generator   : %GENERATOR%
echo Architecture: %ARCH%
echo Build Type  : %BUILD_TYPE%
echo.

set "GEN_DIR=%GENERATOR%"
set "GEN_DIR=%GEN_DIR: =_%"
set "GEN_DIR=%GEN_DIR::=_%"

set "BUILD_DIR=build\%PLATFORM%_%GEN_DIR%_%ARCH%_%BUILD_TYPE%"

echo Build folder:
echo %BUILD_DIR%
echo.

if not exist "%BUILD_DIR%" (
    mkdir "%BUILD_DIR%"
)

set "CONFIG_LOG=%BUILD_DIR%\configure.log"
set "BUILD_LOG=%BUILD_DIR%\build.log"

echo ============================================================
echo                         CONFIGURING
echo ============================================================
echo.

cmake -S . -B "%BUILD_DIR%" -G "%GENERATOR%" %TOOLCHAIN% %EXTRA_CMAKE%

set "CONFIG_RESULT=%ERRORLEVEL%"

echo.

if not "%CONFIG_RESULT%"=="0" (
    echo ============================================================
    echo                   CONFIGURATION FAILED
    echo ============================================================
    echo.
    echo Press any key to close...
    pause >nul
    endlocal
    exit /b %CONFIG_RESULT%
)

echo ============================================================
echo                           BUILDING
echo ============================================================
echo.

if "%MULTI%"=="1" (
    cmake --build "%BUILD_DIR%" --config "%BUILD_TYPE%" --parallel
) else (
    cmake --build "%BUILD_DIR%" --parallel
)

set "BUILD_RESULT=%ERRORLEVEL%"

echo.
echo ============================================================
echo                         BUILD RESULT
echo ============================================================
echo.

if "%BUILD_RESULT%"=="0" (

    echo BUILD SUCCESSFUL.
    echo.
    echo Build directory:
    echo %CD%\%BUILD_DIR%
    echo.

    if exist "%BUILD_DIR%" (
        echo Opening build directory...
        start "" explorer.exe "%CD%\%BUILD_DIR%"
    )

    if /I "%RUN_INSTALL%"=="yes" (
        echo.
        echo Installing...

        if "%MULTI%"=="1" (
            cmake --install "%BUILD_DIR%" --config "%BUILD_TYPE%"
        ) else (
            cmake --install "%BUILD_DIR%"
        )

        if errorlevel 1 (
            echo.
            echo INSTALL FAILED.
            set "BUILD_RESULT=1"
        ) else (
            echo.
            echo INSTALL SUCCESSFUL.
        )
    )

) else (

    echo BUILD FAILED.
    echo.
    echo Build directory:
    echo %CD%\%BUILD_DIR%
)

echo.
echo ============================================================
echo                           FINISHED
echo ============================================================
echo.
echo Press any key to close...
pause >nul

endlocal
exit /b %BUILD_RESULT%
