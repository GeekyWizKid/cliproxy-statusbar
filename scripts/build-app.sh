#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CliproxyStatusBar"
BUNDLE_ID="${BUNDLE_ID:-io.github.cliproxy.statusbar}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
RAW_VERSION="${VERSION:-0.2.0}"
SHORT_VERSION="${RAW_VERSION#v}"
if [[ -z "$SHORT_VERSION" ]]; then
  SHORT_VERSION="0.2.0"
fi

RAW_BUILD_NUMBER="${BUILD_NUMBER:-$SHORT_VERSION}"
BUNDLE_VERSION="$(printf '%s' "$RAW_BUILD_NUMBER" | tr -cd '0-9.')"
if [[ -z "$BUNDLE_VERSION" ]]; then
  BUNDLE_VERSION="1"
fi

CACHE_DIR="${SWIFT_LOCAL_CACHE_DIR:-$ROOT_DIR/.swift-cache}"
mkdir -p "$CACHE_DIR/.swiftpm" "$CACHE_DIR/clang"
export SWIFTPM_CONFIG_PATH="${SWIFTPM_CONFIG_PATH:-$CACHE_DIR/.swiftpm}"
export SWIFTPM_SECURITY_PATH="${SWIFTPM_SECURITY_PATH:-$CACHE_DIR/.swiftpm}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$CACHE_DIR/clang}"

pushd "$ROOT_DIR" >/dev/null

echo "Building ${APP_NAME} (${CONFIGURATION})..."
swift build --disable-sandbox -c "$CONFIGURATION" --product "$APP_NAME"

BIN_DIR="$(swift build --disable-sandbox -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"
if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Executable not found: $EXECUTABLE_PATH" >&2
  exit 1
fi

APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${SHORT_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUNDLE_VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "Built app bundle: $APP_DIR"

popd >/dev/null
