#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/dist"
BIN_DIR="$ROOT_DIR/addons/codis_serial/bin"

mkdir -p "$OUT_DIR"
ZIP_NAME="$OUT_DIR/codis_serial_artifacts.zip"

rm -f "$ZIP_NAME"
cd "$ROOT_DIR"
zip -r "$ZIP_NAME" addons/codis_serial/bin addons/codis_serial/README.md addons/codis_serial/plugin.cfg

echo "Packaged artifacts into $ZIP_NAME"
