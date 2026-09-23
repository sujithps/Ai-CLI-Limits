#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="${1:-$HOME/Applications/Limits.app}"
BIN="$APP/Contents/MacOS/Limits"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Without an explicit target, swiftc stamps the host OS as the minimum and the
# app refuses to launch on anything older.
TARGET="$(uname -m)-apple-macos14.0"

swiftc -O -swift-version 5 -target "$TARGET" \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  -framework ServiceManagement -framework Security -lsqlite3 \
  -o "$BIN" Sources/*.swift

codesign --force --sign - "$APP"
echo "built $APP"
