$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).ProviderPath
$nativeSrc = Join-Path $repoRoot 'addons\codis_serial\native'
$godotCppSource = if ($env:GODOTCPP_SOURCE_DIR) { $env:GODOTCPP_SOURCE_DIR } else { Join-Path $nativeSrc 'godot-cpp' }
$ndkRoot = if ($env:ANDROID_NDK_ROOT) { $env:ANDROID_NDK_ROOT } elseif ($env:ANDROID_NDK_HOME) { $env:ANDROID_NDK_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk\ndk\27.2.12479018' }
$ndkRoot = $ndkRoot.Trim().Trim([char[]]@(39, 34))
$toolchain = Join-Path $ndkRoot 'build\cmake\android.toolchain.cmake'

if (-not (Test-Path (Join-Path $godotCppSource 'CMakeLists.txt'))) {
    throw "godot-cpp source tree not found: $godotCppSource"
}
if (-not (Test-Path $toolchain)) {
    throw "Android NDK toolchain not found: $toolchain"
}

$abis = if ($env:ANDROID_ABIS) { $env:ANDROID_ABIS -split '[,; ]+' | Where-Object { $_ } } else { @('arm64-v8a', 'armeabi-v7a') }
$archNames = @{
    'arm64-v8a' = 'arm64'
    'armeabi-v7a' = 'arm32'
    'x86_64' = 'x86_64'
    'x86' = 'x86_32'
}

foreach ($abi in $abis) {
    if (-not $archNames.ContainsKey($abi)) {
        throw "Unsupported Android ABI: $abi"
    }

    foreach ($target in @('template_debug', 'template_release')) {
        $buildDir = Join-Path $repoRoot "build\android-windows-$abi-$target"
        $buildType = if ($target -eq 'template_debug') { 'Debug' } else { 'Release' }
        $configureArgs = @(
            '-S', $nativeSrc, '-B', $buildDir, '-G', 'Ninja',
            "-DGODOTCPP_SOURCE_DIR=$godotCppSource",
            "-DGODOTCPP_TARGET=$target",
            "-DCMAKE_BUILD_TYPE=$buildType",
            "-DANDROID_ABI=$abi",
            '-DANDROID_PLATFORM=android-21',
            "-DCMAKE_TOOLCHAIN_FILE=$toolchain"
        )

        Write-Host "Configuring Android $abi ($target)..."
        & cmake @configureArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Android $abi $target CMake configuration failed with exit code $LASTEXITCODE."
        }

        Write-Host "Building Android $abi ($target)..."
        & cmake --build $buildDir --parallel
        if ($LASTEXITCODE -ne 0) {
            throw "Android $abi $target build failed with exit code $LASTEXITCODE."
        }

        $artifact = Join-Path $repoRoot "addons\codis_serial\bin\android\codis_serial.$($archNames[$abi]).android.$target.so"
        if (-not (Test-Path $artifact)) {
            throw "Android $abi library was not produced at $artifact."
        }
        Write-Host "Android $abi ($target) built: $artifact"
    }
}
