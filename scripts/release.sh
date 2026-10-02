#!/bin/zsh
#
# Builds a signed, notarized, stapled Annoynt.dmg (Developer ID, universal) and
# publishes it as a GitHub Release on this repo under tag vX.Y.Z.
# Adapted from the macos-sparkle-release pipeline, minus Sparkle: one public repo,
# no appcast — users download new versions from the Releases page.
#
# The version comes from Resources/Info.plist: bump CFBundleShortVersionString
# (becomes the tag) and CFBundleVersion first, commit, and push.
#
# One-time setup:
#   1. A "Developer ID Application" certificate in the login keychain.
#   2. A notarytool keychain profile (any profile for team $TEAM_ID works):
#        xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#          --apple-id "<apple-id-email>" --team-id "$TEAM_ID" --password "<app-specific-password>"
#   3. brew install create-dmg gh && gh auth login
#
# Keep the login keychain unlocked for the whole run (both notarizations read it),
# and don't pipe through tee — it masks the exit code.
#
#   scripts/release.sh > release.log 2>&1; echo "exit: $?"
#
set -euo pipefail

# ---- Config -------------------------------------------------------------
APP_NAME="Annoynt"
TEAM_ID="L8SC3933M5"
NOTARY_PROFILE="${NOTARY_PROFILE:-DockLockr}"   # team-wide credentials, shared with DockLockr
REPO_SLUG="biozalp/annoynt"
DEV_ID="${DEV_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
# ------------------------------------------------------------------------

ROOT="${0:A:h}/.."
ROOT="${ROOT:A}"
cd "$ROOT"
BUILD_DIR="$ROOT/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
DMG_STAGE="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
BG="$ROOT/dmg-assets/background.png"

VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
BUILD="$(plutil -extract CFBundleVersion raw Resources/Info.plist)"
TAG="v$VERSION"

# notarytool exits 0 even for an "Invalid" verdict, so check the status line.
notarize() {
  local out
  out="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || { echo "$out"; exit 1; }
  echo "$out"
  [[ "$out" == *"status: Accepted"* ]] || { echo "ERROR: notarization of ${1:t} was not accepted (see notarytool log)."; exit 1; }
}

echo "==> 0/7  Pre-flight for $APP_NAME $VERSION ($BUILD)…"
[ -n "$DEV_ID" ] || { echo "ERROR: no Developer ID Application certificate found."; exit 1; }
# A 403 "required agreement is missing" here means the Account Holder must accept the
# Apple Developer Program License Agreement — not a credential problem.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not logged in."; exit 1; }
command -v create-dmg >/dev/null || { echo "ERROR: brew install create-dmg"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "ERROR: uncommitted changes — the release must match a pushed commit."; exit 1; }
git fetch -q origin
COMMIT="$(git rev-parse HEAD)"
[ "$COMMIT" = "$(git rev-parse origin/main)" ] || { echo "ERROR: HEAD is not origin/main — push first."; exit 1; }
if [ "${ALLOW_RERELEASE:-0}" != 1 ] && gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  echo "ERROR: release $TAG already exists. Bump the version, or ALLOW_RERELEASE=1 to replace its DMG."; exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 1/7  Building universal app, signed with $DEV_ID…"
SIGN_IDENTITY="$DEV_ID" UNIVERSAL=1 "$ROOT/scripts/build-app.sh"

echo "==> 2/7  Verifying signature, hardened runtime and architectures…"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
# Captured, not piped into grep -q: with pipefail, grep's early exit SIGPIPEs the producer.
SIG_INFO="$(codesign -dv "$APP_PATH" 2>&1)"
[[ "$SIG_INFO" == *"(runtime)"* ]] || { echo "ERROR: hardened runtime not enabled."; exit 1; }
ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"
[[ "$ARCHS" == *x86_64* && "$ARCHS" == *arm64* ]] || { echo "ERROR: not a universal binary ($ARCHS)."; exit 1; }

echo "==> 3/7  Notarizing the app…"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
notarize "$ZIP_PATH"

echo "==> 4/7  Stapling the app…"
xcrun stapler staple "$APP_PATH"

echo "==> 5/7  Building the styled DMG…"
[ -f "$BG" ] || swift "$ROOT/scripts/dmg-background.swift"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"
create-dmg \
  --volname "$APP_NAME" \
  --volicon "$ROOT/Resources/AppIcon.icns" \
  --background "$BG" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "$APP_NAME.app" 150 215 \
  --app-drop-link 450 215 \
  --hide-extension "$APP_NAME.app" \
  --no-internet-enable \
  "$DMG_PATH" "$DMG_STAGE"

echo "==> 6/7  Notarizing + stapling the DMG…"
notarize "$DMG_PATH"
xcrun stapler staple "$DMG_PATH"

echo "==> 7/7  Publishing GitHub Release $TAG…"
NOTES="$BUILD_DIR/notes.md"
cat > "$NOTES" <<EOF
**Download [$APP_NAME.dmg](https://github.com/$REPO_SLUG/releases/download/$TAG/$APP_NAME.dmg)**, open it, and drag $APP_NAME into Applications.

On first launch, allow $APP_NAME under **System Settings › Privacy & Security › Accessibility**. It needs this to catch your Spaces shortcuts and trackpad swipes.

- Requires macOS 14 or later (developed and calibrated on macOS 27). Universal: Apple Silicon and Intel.
- Signed with Developer ID and notarized by Apple.
EOF
if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG_PATH" --repo "$REPO_SLUG" --clobber
else
  gh release create "$TAG" "$DMG_PATH" --repo "$REPO_SLUG" --target "$COMMIT" \
    --title "$APP_NAME $VERSION" --notes-file "$NOTES"
fi

echo
echo "Done. Published $APP_NAME $VERSION from $COMMIT:"
echo "  https://github.com/$REPO_SLUG/releases/tag/$TAG"
echo "  https://github.com/$REPO_SLUG/releases/latest/download/$APP_NAME.dmg"
