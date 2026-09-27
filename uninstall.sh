#!/bin/bash
# Removes AI CLI Limits and everything it stored.
set -euo pipefail

APP="$HOME/Applications/AI CLI Limits.app"

pkill -f "AI CLI Limits.app/Contents/MacOS/AI CLI Limits" 2>/dev/null || true
sleep 1

# Drops the login item registration along with the bundle it points at.
rm -rf "$APP"
defaults delete com.sujithps.ai-cli-limits 2>/dev/null || true

echo "Removed $APP and its preferences."
echo "If it still shows under System Settings, Login Items, remove it there too."
