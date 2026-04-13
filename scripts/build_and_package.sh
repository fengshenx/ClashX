#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

DEVELOPER_ID="Developer ID Application: fengshenx@gmail.com"
TEAM_ID="65B2283FZJ"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"
SCHEME="ClashX"

echo "==> Creating build directory..."
mkdir -p "$BUILD_DIR"

echo "==> Building and archiving..."
xcodebuild -workspace "$PROJECT_DIR/ClashX.xcworkspace" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$BUILD_DIR/ClashX.xcarchive" \
  archive

echo "==> Exporting app..."
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/ClashX.xcarchive" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$BUILD_DIR"

echo "==> Creating DMG with Applications alias..."
# Create a staging dir with app + alias to /Applications
STAGING_DIR="$BUILD_DIR/dmg_staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy app
cp -r "$BUILD_DIR/ClashX.app" "$STAGING_DIR/"

# Create alias to /Applications (will be visible as "Applications" folder link)
ln -s /Applications "$STAGING_DIR/Applications"

# Create DMG
hdiutil create "$BUILD_DIR/ClashX.dmg" \
  -volname "ClashX" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO

rm -rf "$STAGING_DIR"

echo "==> Done! Output:"
ls -lh "$BUILD_DIR/ClashX.dmg"
