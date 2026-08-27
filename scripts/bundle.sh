#!/usr/bin/env bash
# Assemble the compiled binary into a real .app bundle, then sign it.
#
# SwiftPM only produces a bare executable. macOS needs a bundle before it will
# treat this as an app at all: menu bar items, Info.plist settings like
# LSUIElement, and the code identity that Accessibility permission hangs off.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP_NAME="Rephraze"
APP="build/${APP_NAME}.app"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"

# The signing identity. Falls back to ad-hoc ("-") so a fresh clone builds and
# runs immediately -- but ad-hoc means macOS forgets Accessibility permission on
# every rebuild. Run `make cert` once to fix that properly.
SIGN_ID="${REPHRAZE_SIGN_ID:-Rephraze Dev}"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --product "$APP_NAME"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "error: no binary at $BIN_PATH" >&2
  exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH" "$APP/Contents/MacOS/${APP_NAME}"

sed -e "s/__VERSION__/${VERSION}/" \
    -e "s/__BUILD__/${BUILD_NUMBER}/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null

# Signing. Prefer the stable self-signed identity; fall back to ad-hoc.
#
# We just try it rather than asking `security find-identity -v` first, because
# that command hides self-signed certificates -- they chain to no trusted root,
# so it calls them invalid even though codesign accepts them fine.
if codesign --force --sign "$SIGN_ID" --timestamp=none "$APP" 2>/dev/null; then
  echo "==> Signed as '$SIGN_ID' (stable identity, permission survives rebuilds)"
else
  echo "==> Signing ad-hoc -- no '$SIGN_ID' identity available"
  echo "    Heads up: macOS forgets Accessibility permission on every rebuild."
  echo "    Run 'make cert' once to fix that."
  codesign --force --sign - "$APP"
fi

codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

echo "==> Built $APP (version $VERSION, build $BUILD_NUMBER)"
