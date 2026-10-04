@echo off
setlocal

REM === Set this to your Visual Studio path (edit one, comment out the rest) ===

REM VS 2022 Community:
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"

REM VS 2022 BuildTools:
REM call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"

REM VS 2019 Community:
REM call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"

REM VS 2019 BuildTools:
REM call "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"

REM === Build ===
if not exist build mkdir build
cd build
cmake .. -G "NMake Makefiles"
nmake

if %errorlevel% neq 0 (
    echo.
    echo BUILD FAILED
    pause
    exit /b %errorlevel%
)

echo.
echo BUILD SUCCEEDED
pause
