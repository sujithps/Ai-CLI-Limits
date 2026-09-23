#!/bin/bash
# Removes Limits and everything it stored.
set -euo pipefail

APP="$HOME/Applications/Limits.app"

pkill -f "Limits.app/Contents/MacOS/Limits" 2>/dev/null || true
sleep 1

# Drops the login item registration along with the bundle it points at.
rm -rf "$APP"
defaults delete local.limits 2>/dev/null || true

echo "Removed $APP and its preferences."
echo "If it still shows under System Settings, Login Items, remove it there too."
