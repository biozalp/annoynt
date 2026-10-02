#!/usr/bin/env bash
#
# Verifies a published release against what users actually download — the GitHub
# Release asset and the /releases/latest link from the README — not the local build.
#
#   scripts/verify-release.sh [X.Y.Z] [build]     (defaults: Resources/Info.plist)
#
# Exits non-zero if any check fails. Prints one line per check.
set -uo pipefail

cd "$(dirname "$0")/.."
SLUG="biozalp/annoynt"; APP="Annoynt"
VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)}"
BUILD="${2:-$(plutil -extract CFBundleVersion raw Resources/Info.plist)}"
TAG="v$VERSION"
DMG_URL="https://github.com/$SLUG/releases/download/$TAG/$APP.dmg"
LATEST_URL="https://github.com/$SLUG/releases/latest/download/$APP.dmg"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/verify-$APP-XXXX")"
FAILS=0
pass() { echo "  ok    $*"; }
fail() { echo "  FAIL  $*"; FAILS=$((FAILS + 1)); }
MNT=""
cleanup() { [ -n "$MNT" ] && hdiutil detach "$MNT" -quiet 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

echo "== $APP $VERSION ($BUILD) from $SLUG"

if ! curl -fsSL -o "$WORK/$APP.dmg" "$DMG_URL"; then
  fail "download $DMG_URL"; echo "$FAILS check(s) failed"; exit 1
fi
pass "downloaded $APP.dmg ($(stat -f %z "$WORK/$APP.dmg") bytes)"

# Browsers quarantine downloads; assess the DMG the way Gatekeeper would see it.
xattr -w com.apple.quarantine "0081;$(printf '%x' "$(date +%s)");Safari;" "$WORK/$APP.dmg"

xcrun stapler validate "$WORK/$APP.dmg" >/dev/null 2>&1 \
  && pass "DMG notarization ticket stapled" || fail "DMG stapler validate"

MNT=$(hdiutil attach -nobrowse -readonly "$WORK/$APP.dmg" 2>/dev/null | tail -1 | awk -F'\t' '{print $NF}')
BUNDLE="$MNT/$APP.app"
[ -d "$BUNDLE" ] || { fail "no $APP.app inside the DMG"; echo "$FAILS check(s) failed"; exit 1; }
[ -L "$MNT/Applications" ] && pass "Applications drop link present" || fail "no Applications link in the DMG"

GK=$(spctl -a -vv "$BUNDLE" 2>&1)
if echo "$GK" | grep -q "accepted" && echo "$GK" | grep -q "Notarized Developer ID"; then
  pass "Gatekeeper: accepted, Notarized Developer ID"
else
  fail "Gatekeeper: $(echo "$GK" | tr '\n' ' ')"
fi
xcrun stapler validate "$BUNDLE" >/dev/null 2>&1 \
  && pass "app notarization ticket stapled" || fail "app stapler validate"

PLIST="$BUNDLE/Contents/Info.plist"
V=$(plutil -extract CFBundleShortVersionString raw "$PLIST" 2>/dev/null)
B=$(plutil -extract CFBundleVersion raw "$PLIST" 2>/dev/null)
[ "$V" = "$VERSION" ] && pass "CFBundleShortVersionString $V" || fail "CFBundleShortVersionString is '$V', expected $VERSION"
[ "$B" = "$BUILD" ] && pass "CFBundleVersion $B" || fail "CFBundleVersion is '$B', expected $BUILD"
ARCHS=$(lipo -archs "$BUNDLE/Contents/MacOS/$APP" 2>/dev/null)
[[ "$ARCHS" == *x86_64*arm64* || "$ARCHS" == *arm64*x86_64* ]] && pass "universal binary ($ARCHS)" || fail "architectures: $ARCHS"
MINOS=$(vtool -arch arm64 -show-build "$BUNDLE/Contents/MacOS/$APP" 2>/dev/null | awk '/minos/{print $2}')
echo "  info  LSMinimumSystemVersion $(plutil -extract LSMinimumSystemVersion raw "$PLIST"), binary minos $MINOS"
[ -f "$BUNDLE/Contents/Resources/AppIcon.icns" ] && pass "app icon bundled" || fail "AppIcon.icns missing"

# The README's download button points at /releases/latest — it must resolve to this tag.
FINAL=$(curl -fsIL -o /dev/null -w '%{url_effective}' "$LATEST_URL")
[[ "$FINAL" == *"$TAG"* || "$FINAL" == *"objects.githubusercontent"* || "$FINAL" == *"release-assets"* ]] \
  && pass "latest/download resolves ($FINAL)" || fail "latest/download resolved to $FINAL"
LATEST_TAG=$(gh release view --repo "$SLUG" --json tagName -q .tagName 2>/dev/null)
[ "$LATEST_TAG" = "$TAG" ] && pass "latest release is $TAG" || fail "latest release is '$LATEST_TAG', expected $TAG"

echo
if [ "$FAILS" -eq 0 ]; then echo "All checks passed."; else echo "$FAILS check(s) failed."; fi
exit "$FAILS"
