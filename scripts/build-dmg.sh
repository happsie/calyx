#!/bin/bash
set -euo pipefail

APP_NAME="Calyx"
BUNDLE_ID="com.calyx.app"
VERSION="1.0.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release-app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$PROJECT_DIR/$APP_NAME.dmg"

echo "==> Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

echo "==> Generating app icon..."
ICNS_PATH="$BUILD_DIR/AppIcon.icns"
mkdir -p "$BUILD_DIR"
swift "$SCRIPT_DIR/generate-icns.swift" "$ICNS_PATH"

echo "==> Assembling $APP_NAME.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$PROJECT_DIR/.build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy icon
cp "$ICNS_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> Code signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Creating DMG..."
rm -f "$DMG_PATH"

# Create a temporary directory for DMG contents
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

echo ""
echo "Done! Output:"
echo "  App:  $APP_BUNDLE"
echo "  DMG:  $DMG_PATH"
echo ""
echo "To install: open $DMG_PATH and drag $APP_NAME to Applications."
