#!/bin/bash
set -e

# Required environment variables:
#   APPLE_ID       - Apple ID email
#   APPLE_PASSWORD - App-specific password
#   APPLE_TEAM_ID  - Apple Developer Team ID
#   SIGN_IDENTITY  - Code signing identity (e.g. "Developer ID Application: Name (TEAMID)")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
SCHEME="ClashX"

# Validate required env vars
for var in APPLE_ID APPLE_PASSWORD APPLE_TEAM_ID SIGN_IDENTITY; do
  if [ -z "${!var}" ]; then
    echo "Error: $var is not set"
    exit 1
  fi
done

echo "==> Creating build directory..."
mkdir -p "$BUILD_DIR"

echo "==> Generating ExportOptions.plist..."
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingCertificate</key>
    <string>${SIGN_IDENTITY}</string>
    <key>teamID</key>
    <string>${APPLE_TEAM_ID}</string>
</dict>
</plist>
EOF

echo "==> Injecting team ID into plist files..."
HELPER_INFO="$PROJECT_DIR/ProxyConfigHelper/Helper-Info.plist"
APP_INFO="$PROJECT_DIR/ClashX/Info.plist"
sed -i '' "s/__APPLE_TEAM_ID__/$APPLE_TEAM_ID/g" "$HELPER_INFO" "$APP_INFO"

# Restore placeholder on exit (even if script fails)
trap 'sed -i "" "s/$APPLE_TEAM_ID/__APPLE_TEAM_ID__/g" "$HELPER_INFO" "$APP_INFO"' EXIT

echo "==> Building and archiving..."
xcodebuild -workspace "$PROJECT_DIR/ClashX.xcworkspace" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$BUILD_DIR/ClashX.xcarchive" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  archive

echo "==> Exporting app..."
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/ClashX.xcarchive" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$BUILD_DIR"

echo "==> Verifying signature..."
codesign --verify --deep --strict "$BUILD_DIR/ClashX.app"
echo "Signature valid (notarization pending)"

echo "==> Creating zip for notarization..."
ditto -c -k --keepParent "$BUILD_DIR/ClashX.app" "$BUILD_DIR/ClashX_for_notarize.zip"

echo "==> Notarizing..."
xcrun notarytool submit "$BUILD_DIR/ClashX_for_notarize.zip" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

echo "==> Stapling notarization ticket to app..."
xcrun stapler staple "$BUILD_DIR/ClashX.app"

rm -f "$BUILD_DIR/ClashX_for_notarize.zip"

echo "==> Creating DMG with Applications alias..."
STAGING_DIR="$BUILD_DIR/dmg_staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

ditto "$BUILD_DIR/ClashX.app" "$STAGING_DIR/ClashX.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create "$BUILD_DIR/ClashX.dmg" \
  -volname "ClashX" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO

rm -rf "$STAGING_DIR"

echo "==> Done! Output:"
ls -lh "$BUILD_DIR/ClashX.dmg"
