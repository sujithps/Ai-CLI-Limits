#!/bin/bash
# Builds AI CLI Limits and starts it. Safe to re-run to upgrade.
set -euo pipefail

APP="$HOME/Applications/AI CLI Limits.app"

# Piped from curl, there are no sources on disk yet, so fetch them first.
if [ -f "${BASH_SOURCE[0]:-}" ] && [ -d "$(dirname "${BASH_SOURCE[0]}")/Sources" ]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  REPO="${AI_CLI_LIMITS_REPO:-https://github.com/sujithps/Ai-CLI-Limits.git}"
  SRC="$(mktemp -d)/ai-cli-limits"
  echo "Fetching $REPO"
  git clone --depth 1 --quiet "$REPO" "$SRC"
fi

# Before the rename this installed as Limits.app; two copies would show two
# menu bar items, so retire the old one.
if [ -d "$HOME/Applications/Limits.app" ]; then
  echo "Removing the copy installed under the old name, Limits"
  pkill -f "Limits.app/Contents/MacOS/Limits" 2>/dev/null || true
  rm -rf "$HOME/Applications/Limits.app"
  defaults delete local.limits 2>/dev/null || true
fi

# Replacing the binary under a running copy leaves a stale process behind.
if pgrep -f "AI CLI Limits.app/Contents/MacOS/AI CLI Limits" >/dev/null 2>&1; then
  echo "Stopping the running copy"
  pkill -f "AI CLI Limits.app/Contents/MacOS/AI CLI Limits" || true
  sleep 1
fi

"$SRC/build.sh" "$APP"
open "$APP"

cat <<DONE

AI CLI Limits is running. Look for it in the menu bar, near the clock.

macOS will ask once to allow notifications, and may ask once for access to the
Claude Code keychain item; choose Always Allow so it can read usage unattended.

Start it automatically at login from Settings inside the panel.
DONE
