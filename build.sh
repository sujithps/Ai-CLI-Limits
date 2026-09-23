#!/bin/bash
# Compiles Limits.app. Takes an optional destination path.
set -euo pipefail
cd "$(dirname "$0")"

APP="${1:-$HOME/Applications/Limits.app}"
BIN="$APP/Contents/MacOS/Limits"

if ! command -v swiftc >/dev/null 2>&1; then
  cat >&2 <<'MISSING'
swiftc was not found, so there is nothing to build with.

Install Apple's command line tools, then run this again:

    xcode-select --install
MISSING
  exit 1
fi

MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 14 ]; then
  echo "Limits needs macOS 14 or later; this is $(sw_vers -productVersion)." >&2
  exit 1
fi

# Without an explicit target, swiftc stamps the host OS as the minimum and the
# app refuses to launch on anything older.
TARGET="$(uname -m)-apple-macos14.0"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 -target "$TARGET" \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  -framework ServiceManagement -framework Security -lsqlite3 \
  -o "$BIN" Sources/*.swift

codesign --force --sign - "$APP"
echo "built $APP"
