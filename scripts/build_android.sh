#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT_DIR/addons/codis_serial/native"
GODOTCPP_SOURCE_DIR="${GODOTCPP_SOURCE_DIR:-$SRC_DIR/godot-cpp}"
ANDROID_OUT="$ROOT_DIR/addons/codis_serial/bin/android"
read -r -a ABIS <<< "${ANDROID_ABIS:-arm64-v8a armeabi-v7a}"
ANDROID_API=21

if [[ -z "${ANDROID_NDK_ROOT:-}" ]]; then
  if [[ "$(uname -s)" == "Linux" ]]; then
    ANDROID_NDK_ROOT="$HOME/Android/Sdk/ndk/27.2.12479018"
  else
    echo "Set ANDROID_NDK_ROOT to an Android NDK with host tools for this OS." >&2
    exit 1
  fi
fi
if [[ ! -f "$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" ]]; then
  echo "Android NDK not found or not usable on this host: $ANDROID_NDK_ROOT" >&2
  echo "On WSL, install the Linux-host NDK using Android SDK Manager." >&2
  exit 1
fi

for ABI in "${ABIS[@]}"; do
  case "$ABI" in
    arm64-v8a) CODIS_ARCH=arm64 ;;
    armeabi-v7a) CODIS_ARCH=arm32 ;;
    x86_64) CODIS_ARCH=x86_64 ;;
    x86) CODIS_ARCH=x86_32 ;;
    *) echo "Unsupported Android ABI: $ABI"; exit 1 ;;
  esac

  for TARGET in template_debug template_release; do
    BUILD_DIR="$ROOT_DIR/build/android-$ABI-$TARGET"
    ARTIFACT="$ANDROID_OUT/codis_serial.$CODIS_ARCH.android.$TARGET.so"
    BUILD_TYPE=Release
    [[ "$TARGET" == template_debug ]] && BUILD_TYPE=Debug
    mkdir -p "$BUILD_DIR"
    echo "Configuring Android $ABI $TARGET extension..."
    cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
      -DGODOTCPP_SOURCE_DIR="$GODOTCPP_SOURCE_DIR" \
      -DGODOTCPP_TARGET="$TARGET" \
      -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
      -DANDROID_ABI="$ABI" \
      -DANDROID_PLATFORM="android-$ANDROID_API" \
      -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
      -G Ninja

    echo "Building Android $ABI $TARGET extension..."
    cmake --build "$BUILD_DIR" --parallel

    if [[ ! -f "$ARTIFACT" ]]; then
      echo "ERROR: Android extension for $ABI not found at $ARTIFACT"
      exit 1
    fi
    echo "Android $ABI $TARGET built: $ARTIFACT"
  done
done

echo "Android extension builds complete."
