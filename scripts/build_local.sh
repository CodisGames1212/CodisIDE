#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT_DIR/addons/codis_serial/native"
GODOTCPP_SOURCE_DIR="${GODOTCPP_SOURCE_DIR:-$SRC_DIR/godot-cpp}"
for TARGET in template_debug template_release; do
  BUILD_DIR="$ROOT_DIR/build/linux-x86_64-$TARGET"
  OUT_FILE="$ROOT_DIR/addons/codis_serial/bin/linux/codis_serial.linux.$TARGET.so"
  BUILD_TYPE=Release
  [[ "$TARGET" == template_debug ]] && BUILD_TYPE=Debug
  mkdir -p "$BUILD_DIR"

  echo "Configuring Linux x86_64 $TARGET extension..."
  cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
    -DGODOTCPP_SOURCE_DIR="$GODOTCPP_SOURCE_DIR" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DGODOTCPP_TARGET="$TARGET" \
    -G Ninja

  echo "Building Linux x86_64 $TARGET extension..."
  cmake --build "$BUILD_DIR" --parallel

  if [[ ! -f "$OUT_FILE" ]]; then
    echo "ERROR: Linux extension was not produced at $OUT_FILE"
    exit 1
  fi

  echo "Linux x86_64 $TARGET extension built: $OUT_FILE"
done
