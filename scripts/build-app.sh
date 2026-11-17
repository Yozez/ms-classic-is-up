#!/usr/bin/env bash
# Builds a release binary and wraps it in a minimal, ad-hoc signed .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MS Classic Is Up"
EXECUTABLE="MSClassicTray"
APP="$ROOT/build/$APP_NAME.app"

cd "$ROOT"
swift build -c release --product "$EXECUTABLE"
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc sign with the hardened runtime and App Sandbox (see Resources/MSClassicTray.entitlements).
codesign --force --sign - --timestamp=none --options runtime \
  --entitlements "$ROOT/Resources/MSClassicTray.entitlements" "$APP"
echo "Built: $APP"
