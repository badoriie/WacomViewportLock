#!/usr/bin/env bash
# Builds a release binary and wraps it in build/WacomViewportLock.app (ad-hoc signed).
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="WacomViewportLock"
APP_DIR="build/${APP_NAME}.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# Set SIGN_IDENTITY to a Developer ID / Apple Development identity to keep the
# Accessibility grant stable across rebuilds; ad-hoc ("-") works but may need re-granting.
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP_DIR"

echo "Built $APP_DIR"
