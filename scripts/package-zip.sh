#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CliproxyStatusBar"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
RAW_VERSION="${VERSION:-dev}"
SAFE_VERSION="$(printf '%s' "$RAW_VERSION" | tr '/ ' '--')"

APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
if [[ ! -d "$APP_DIR" ]]; then
  echo "App bundle not found: $APP_DIR" >&2
  echo "Run ./scripts/build-app.sh first." >&2
  exit 1
fi

ZIP_PATH="$OUTPUT_DIR/${APP_NAME}-${SAFE_VERSION}-macOS.zip"
rm -f "$ZIP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Created archive: $ZIP_PATH"
