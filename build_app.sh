#!/usr/bin/env bash
# Builds a release binary and wraps it in build/WacomViewportLock.app (ad-hoc signed).
#
# Optional environment:
#   VERSION        marketing version written to the bundle, e.g. 1.2.0 (default: keep Info.plist's)
#   BUILD_NUMBER   CFBundleVersion (default: keep Info.plist's)
#   SIGN_IDENTITY  codesigning identity (default: ad-hoc "-")
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="WacomViewportLock"
APP_DIR="build/${APP_NAME}.app"

swift build -c release --only-use-versions-from-resolved-file
BIN_DIR="$(swift build -c release --only-use-versions-from-resolved-file --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
# Sparkle (auto-updates). ditto keeps the framework's Versions/Current symlinks intact.
ditto "$BIN_DIR/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

PLIST="$APP_DIR/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
fi

# Set SIGN_IDENTITY to a Developer ID / Apple Development identity to keep the
# Accessibility grant stable across rebuilds; ad-hoc ("-") works but may need re-granting.
IDENTITY="${SIGN_IDENTITY:--}"
# Sign nested code inside-out (Sparkle's helpers, then the framework, then the app);
# --deep is unreliable for this per Apple's and Sparkle's docs.
SPARKLE="$APP_DIR/Contents/Frameworks/Sparkle.framework"
for nested in "$SPARKLE"/Versions/B/XPCServices/*.xpc "$SPARKLE/Versions/B/Autoupdate" \
    "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do
    codesign --force --sign "$IDENTITY" "$nested"
done
codesign --force --sign "$IDENTITY" "$APP_DIR"

echo "Built $APP_DIR"
