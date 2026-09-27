#!/bin/bash
# Compiles AI CLI Limits.app. Takes an optional destination path.
set -euo pipefail
cd "$(dirname "$0")"

APP="${1:-$HOME/Applications/AI CLI Limits.app}"
BIN="$APP/Contents/MacOS/AI CLI Limits"

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
  echo "AI CLI Limits needs macOS 14 or later; this is $(sw_vers -productVersion)." >&2
  exit 1
fi

# Without an explicit target, swiftc stamps the host OS as the minimum and the
# app refuses to launch on anything older.
TARGET="$(uname -m)-apple-macos14.0"
SDK="$(Tools/sdk.sh)"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# $SDK is unquoted on purpose: it is empty or two words.
swiftc -O -swift-version 5 -target "$TARGET" $SDK \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  -framework ServiceManagement -framework Security -lsqlite3 \
  -o "$BIN" Sources/*.swift

codesign --force --sign - "$APP"
echo "built $APP"
