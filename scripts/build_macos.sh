#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS with Xcode command-line tools installed." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT_DIR/addons/codis_serial/native"
GODOTCPP_SOURCE_DIR="${GODOTCPP_SOURCE_DIR:-$SRC_DIR/godot-cpp}"
for TARGET in template_debug template_release; do
  BUILD_DIR="$ROOT_DIR/build/macos-universal-$TARGET"
  OUT_FILE="$ROOT_DIR/addons/codis_serial/bin/macos/codis_serial.macos.$TARGET.dylib"
  BUILD_TYPE=Release
  [[ "$TARGET" == template_debug ]] && BUILD_TYPE=Debug

  cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja \
    -DGODOTCPP_SOURCE_DIR="$GODOTCPP_SOURCE_DIR" \
    -DGODOTCPP_TARGET="$TARGET" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_OSX_ARCHITECTURES="${MACOS_ARCHS:-arm64;x86_64}"
  cmake --build "$BUILD_DIR" --parallel

  test -f "$OUT_FILE" || { echo "macOS extension missing: $OUT_FILE" >&2; exit 1; }
  echo "macOS $TARGET extension built: $OUT_FILE"
done
