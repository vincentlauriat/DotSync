#!/usr/bin/env bash
# Build a Release DotSync.app, Developer ID sign with Hardened Runtime,
# notarize via Apple, staple the ticket, and package it as a distributable .dmg.
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ SPARKLE SIGNING KEY — DO NOT REGENERATE                                    │
# │ Private key: login keychain, account "DotSync" (backup:                    │
# │ ~/.sparkle-keys/DotSync-private-key.txt). Public half = SUPublicEDKey in   │
# │ project.yml: tc95v6kdkHLKWo/LR5v/WqiVYAvV7cNIH4oo2f/hIic=                  │
# │ A new key makes every installed DotSync reject all future updates.         │
# └──────────────────────────────────────────────────────────────────────────┘
#
# Usage: ./Scripts/release.sh <version>
#   e.g. ./Scripts/release.sh 0.5.1
#
# Prerequisites (one-time setup, see MEMORY.md):
#   - "Developer ID Application: Vincent LAURIAT (KFLACS69T9)" certificate in
#     the login keychain (created via Xcode → Settings → Accounts → Manage
#     Certificates).
#   - notarytool credentials under the shared keychain profile "AppliMacVincentGithub".
#
# Override defaults if needed:
#   SIGNING_IDENTITY="Developer ID Application: …"  ./Scripts/release.sh 0.5.1
#   NOTARY_PROFILE="AppliMacVincentGithub"   ./Scripts/release.sh 1.0.0
#
# Outputs release/DotSync-<version>.dmg, fully notarized. Release notes
# live in release/release-notes-<version>.md (write them before publishing).
# Does NOT push to GitHub — prints the suggested `gh release create` command.

set -euo pipefail

VERSION="${1:?Usage: ./Scripts/release.sh <version>  (e.g. ./Scripts/release.sh 0.3.0)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 1. Sanity check: project.yml must declare the same MARKETING_VERSION
if ! grep -q "MARKETING_VERSION: \"$VERSION\"" project.yml; then
  echo "✗ MARKETING_VERSION in project.yml does not match $VERSION" >&2
  echo "  Found:" >&2
  grep "MARKETING_VERSION" project.yml | sed 's/^/    /' >&2
  echo "  Bump project.yml first, then re-run." >&2
  exit 1
fi

# 3. Regenerate xcodeproj
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "✗ XcodeGen not installed. brew install xcodegen" >&2
  exit 1
fi
echo "→ xcodegen generate"
xcodegen generate >/dev/null

# 4. Build Release
# CODE_SIGNING_ALLOWED=NO works around the macOS Sequoia
# `com.apple.provenance` xattr that breaks ad-hoc codesign in CLI.
# We sign manually below after a clean xattr scrub.
echo "→ xcodebuild Release"
xcodebuild -project DotSync.xcodeproj \
  -scheme DotSync \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5

APP="$ROOT/build/Build/Products/Release/DotSync.app"
if [ ! -d "$APP" ]; then
  echo "✗ Build did not produce $APP" >&2
  exit 1
fi

# 5. Stage to a clean directory, Developer ID sign with Hardened Runtime, package.
# Direct in-place codesign fails because Xcode's post-build `lsregister`
# adds `com.apple.provenance` xattrs, which `codesign --force` rejects with
# "resource fork, Finder information, or similar detritus not allowed".
# `ditto --noextattr` copies without xattrs and survives.
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Vincent LAURIAT (KFLACS69T9)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AppliMacVincentGithub}"

STAGING_DIR="$(mktemp -d)"
STAGING="$STAGING_DIR/DotSync.app"
echo "→ Staging to $STAGING_DIR"
ditto --norsrc --noextattr --noacl "$APP" "$STAGING"

# Apple's timestamp.apple.com is intermittently flaky — we've seen
# "A timestamp was expected but was not found." mid-pipeline several times.
# Retry up to 5 times with a short backoff before giving up.
codesign_ts() {
  local target="$1"
  local attempt
  for attempt in 1 2 3 4 5; do
    if codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$target" 2>&1; then
      return 0
    fi
    if [ "$attempt" -lt 5 ]; then
      echo "  ↻ codesign failed (attempt $attempt/5), retrying in 5s…"
      sleep 5
    fi
  done
  echo "✗ codesign $target failed after 5 attempts" >&2
  return 1
}

echo "→ Codesigning Sparkle.framework nested binaries (deepest first)"
SPARKLE_FW="$STAGING/Contents/Frameworks/Sparkle.framework"
SPARKLE_VER="$SPARKLE_FW/Versions/B"
codesign_ts "$SPARKLE_VER/Autoupdate"
codesign_ts "$SPARKLE_VER/XPCServices/Downloader.xpc"
codesign_ts "$SPARKLE_VER/XPCServices/Installer.xpc"
codesign_ts "$SPARKLE_VER/Updater.app"
codesign_ts "$SPARKLE_FW"

echo "→ Codesigning the app itself with Developer ID + Hardened Runtime"
codesign_ts "$STAGING"
codesign --verify --strict --deep "$STAGING"

RELEASE_DIR="$ROOT/release"
mkdir -p "$RELEASE_DIR"
DMG="$RELEASE_DIR/DotSync-$VERSION.dmg"
rm -f "$DMG"

# 5b. Build a friendly installer layout: signed .app on the left, /Applications
# alias on the right, with a background image showing an arrow between them.
DMG_VOLNAME="DotSync $VERSION"
DMG_LAYOUT_DIR="$STAGING_DIR/dmg-layout"
mkdir -p "$DMG_LAYOUT_DIR/.background"
ditto --norsrc --noextattr --noacl "$STAGING" "$DMG_LAYOUT_DIR/DotSync.app"
ln -s /Applications "$DMG_LAYOUT_DIR/Applications"
"$ROOT/Scripts/make-dmg-background.swift" "$DMG_LAYOUT_DIR/.background/background.png" >/dev/null

echo "→ Creating writable DMG to configure Finder layout"
RW_DMG="$STAGING_DIR/temp.dmg"
hdiutil create -volname "$DMG_VOLNAME" -srcfolder "$DMG_LAYOUT_DIR" \
  -fs HFS+ -format UDRW -ov "$RW_DMG" >/dev/null

DMG_MOUNT=$(hdiutil attach -nobrowse -noverify -noautoopen "$RW_DMG" \
  | awk -F '\t' 'END {print $NF}')
echo "→ Mounted at $DMG_MOUNT — applying Finder layout via AppleScript"

# Position DotSync.app at (140, 200) and Applications at (400, 200),
# in a 540 × 380 window. The background paints the arrow between them.
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$DMG_VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 100, 740, 480}
        set view_options to the icon view options of container window
        set arrangement of view_options to not arranged
        set icon size of view_options to 128
        set background picture of view_options to file ".background:background.png"
        set position of item "DotSync.app" of container window to {140, 200}
        set position of item "Applications" of container window to {400, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Make sure the .DS_Store is flushed before unmounting
sync
hdiutil detach "$DMG_MOUNT" -quiet

echo "→ Converting RW DMG to compressed read-only $DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null

rm -rf "$STAGING_DIR"

# 6. Notarize the DMG with Apple, then staple the ticket so the app
# launches on machines without internet access.
echo "→ Submitting $DMG to Apple notary service (this takes 2–5 min)"
xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "→ Stapling notarization ticket to the DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# 7. Sign the DMG with the Sparkle EdDSA key and generate / refresh
# `appcast.xml` so the in-app updater (Sparkle 2) can serve this version.
SPARKLE_VERSION="2.9.1"
SPARKLE_TOOLS="$ROOT/.sparkle-tools"
if [ ! -x "$SPARKLE_TOOLS/bin/sign_update" ]; then
  echo "→ Fetching Sparkle $SPARKLE_VERSION tools (one-time setup)"
  mkdir -p "$SPARKLE_TOOLS"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    | tar -xJ -C "$SPARKLE_TOOLS"
fi

echo "→ Signing $DMG with Sparkle EdDSA key"
# `sign_update` returns: sparkle:edSignature="..." length="<bytes>"
# (so we don't add `length=` ourselves on the <enclosure> — that would duplicate).
SPARKLE_SIG_LINE=$("$SPARKLE_TOOLS/bin/sign_update" --account "DotSync" "$DMG")

# Sparkle compares <sparkle:version> against the running app's CFBundleVersion
# (a monotonically increasing build number), NOT against the marketing version.
# If we put "0.7.0" here while the installed app reports CFBundleVersion="1",
# Sparkle's standard comparator sees [0,7,0] < [1] and concludes "up to date".
# Read the actual CFBundleVersion baked into the .app and use that.
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")

echo "→ Writing $ROOT/appcast.xml (sparkle:version=$BUILD_NUMBER, shortVersionString=$VERSION)"
PUB_DATE=$(date -R)
cat > "$ROOT/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>DotSync</title>
    <link>https://raw.githubusercontent.com/vincentlauriat/DotSync/main/appcast.xml</link>
    <description>DotSync release feed</description>
    <language>en</language>
    <item>
      <title>v$VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/vincentlauriat/DotSync/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure
        url="https://github.com/vincentlauriat/DotSync/releases/download/v$VERSION/DotSync-$VERSION.dmg"
        type="application/octet-stream"
        $SPARKLE_SIG_LINE />
    </item>
  </channel>
</rss>
APPCAST

DMG_SIZE=$(ls -lh "$DMG" | awk '{print $5}')
echo ""
echo "✅ Built, signed, notarized, stapled and Sparkle-signed: $DMG ($DMG_SIZE)"
echo "✅ appcast.xml written for v$VERSION"
echo ""
echo "Next steps to publish on GitHub:"
echo "  1. gh release create v$VERSION ./release/DotSync-$VERSION.dmg --title \"v$VERSION\" --notes-file release/release-notes-$VERSION.md"
echo "  2. git add appcast.xml && git commit -m 'docs: appcast for v$VERSION' && git push"
echo ""
echo "After both, Sparkle clients on older versions will be offered the update on next check."
