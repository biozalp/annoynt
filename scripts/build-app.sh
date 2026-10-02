#!/bin/zsh
# Builds Annoynt.app into ./build and signs it.
#
#   scripts/build-app.sh            # build + sign (local development)
#   scripts/build-app.sh --install  # also copy to /Applications and relaunch
#
# Signing: your "Apple Development" certificate is picked up automatically, which
# keeps the Accessibility grant valid across rebuilds (an ad-hoc signature changes
# every build and macOS silently revokes the grant). Override with
# SIGN_IDENTITY="..." or SIGN_IDENTITY=- for ad-hoc (e.g. building from a fork
# without certificates). A "Developer ID" identity also enables the hardened
# runtime and a secure timestamp, as notarization requires.
#
# UNIVERSAL=1 builds for both Apple Silicon and Intel (used by release.sh).
set -euo pipefail

cd "${0:A:h}/.."
APP=build/Annoynt.app

ARCH_FLAGS=()
[[ "${UNIVERSAL:-0}" == 1 ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/Annoynt"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Annoynt"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$IDENTITY")
[[ "$IDENTITY" == "Developer ID"* ]] && SIGN_FLAGS+=(--options runtime --timestamp)
codesign "${SIGN_FLAGS[@]}" "$APP"
echo "Built $APP (signed: $IDENTITY)"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Annoynt 2>/dev/null || true
  rm -rf /Applications/Annoynt.app
  cp -R "$APP" /Applications/
  open /Applications/Annoynt.app
  echo "Installed to /Applications and launched"
fi
