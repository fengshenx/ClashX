#!/bin/bash
set -e

# Required environment variables:
#   SIGN_IDENTITY  - Code signing identity (e.g. "Developer ID Application: Name (TEAMID)")
#                    (SIGN_ID is accepted as a fallback)
#   NOTARY_PROFILE - notarytool keychain profile name (e.g. APPDEV_NOTARY_PROFILE),
#                    OR set APPLE_ID + APPLE_PASSWORD for app-specific-password auth
#   APPLE_TEAM_ID  - Apple Developer Team ID (optional: parsed from SIGN_IDENTITY if omitted)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
SCHEME="ClashX"

# Fall back to SIGN_ID if SIGN_IDENTITY is not set
SIGN_IDENTITY="${SIGN_IDENTITY:-$SIGN_ID}"

# Derive team ID from the signing identity if not provided, e.g. "... (65B2283FZJ)"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-$(echo "$SIGN_IDENTITY" | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p')}"

# Validate required env vars
if [ -z "$SIGN_IDENTITY" ] || [ -z "$APPLE_TEAM_ID" ]; then
  echo "Error: set SIGN_IDENTITY to a 'Developer ID Application: Name (TEAMID)' identity"
  exit 1
fi
if [ -z "$NOTARY_PROFILE" ] && { [ -z "$APPLE_ID" ] || [ -z "$APPLE_PASSWORD" ]; }; then
  echo "Error: set NOTARY_PROFILE, or APPLE_ID + APPLE_PASSWORD for notarization"
  exit 1
fi

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

# Xcode embeds x86_64-only copies of the Swift standard library for the 10.14
# back-deployment target. The arm64 build loads the system runtime instead, so
# those copies are dead weight (~11 MB) - drop them and re-sign the app.
echo "==> Stripping x86_64-only Swift runtime copies..."
for f in "$BUILD_DIR/ClashX.app/Contents/Frameworks"/*; do
  [ -f "$f" ] || continue
  if lipo -info "$f" 2>/dev/null | grep -q " architecture: x86_64$"; then
    rm -f "$f"
  fi
done

echo "==> Re-signing app..."
codesign --force --options runtime --timestamp \
  --entitlements "$PROJECT_DIR/ClashX/ClashX.entitlements" \
  --sign "$SIGN_IDENTITY" "$BUILD_DIR/ClashX.app"

echo "==> Verifying signature..."
codesign --verify --deep --strict "$BUILD_DIR/ClashX.app"
echo "Signature valid (notarization pending)"

echo "==> Creating zip for notarization..."
ditto -c -k --keepParent "$BUILD_DIR/ClashX.app" "$BUILD_DIR/ClashX_for_notarize.zip"

# notarytool follows the system proxy, and the upload is a ~24 MB multipart PUT.
# With a second proxy client also enabled the upload crosses two proxies and
# stalls with HTTPClientError.deadlineExceeded, so show the path and retry.
echo "==> Checking the notarization upload path..."
PROXY_PORT=$(scutil --proxy | awk '/HTTPSPort :/ {print $3}')
if [ -n "$PROXY_PORT" ]; then
  PROXY_OWNER=$(lsof -nP -iTCP:"$PROXY_PORT" -sTCP:LISTEN 2>/dev/null | sed -n '2p' | awk '{print $1}')
  echo "    system HTTPS proxy: 127.0.0.1:$PROXY_PORT (${PROXY_OWNER:-unknown})"
fi

notarize() {
  if [ -n "$NOTARY_PROFILE" ]; then
    xcrun notarytool submit "$BUILD_DIR/ClashX_for_notarize.zip" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
  else
    xcrun notarytool submit "$BUILD_DIR/ClashX_for_notarize.zip" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait
  fi
}

echo "==> Notarizing..."
for attempt in 1 2 3; do
  if notarize; then
    break
  fi
  if [ "$attempt" = 3 ]; then
    echo "Error: notarization failed after 3 attempts." >&2
    echo "If another proxy client also enables its system proxy or TUN, the upload" >&2
    echo "runs through two proxies and times out - keep only one of them enabled." >&2
    exit 1
  fi
  echo "Attempt $attempt failed, retrying in 5s..."
  sleep 5
done

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
