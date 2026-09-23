#!/bin/bash
# Builds Limits and starts it. Safe to re-run to upgrade.
set -euo pipefail

APP="$HOME/Applications/Limits.app"

# Piped from curl, there are no sources on disk yet, so fetch them first.
if [ -f "${BASH_SOURCE[0]:-}" ] && [ -d "$(dirname "${BASH_SOURCE[0]}")/Sources" ]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  REPO="${LIMITS_REPO:-}"
  if [ -z "$REPO" ]; then
    echo "Set LIMITS_REPO to the git URL to install from, or run this inside a clone." >&2
    exit 1
  fi
  SRC="$(mktemp -d)/limits"
  echo "Fetching $REPO"
  git clone --depth 1 --quiet "$REPO" "$SRC"
fi

# Replacing the binary under a running copy leaves a stale process behind.
if pgrep -f "Limits.app/Contents/MacOS/Limits" >/dev/null 2>&1; then
  echo "Stopping the running copy"
  pkill -f "Limits.app/Contents/MacOS/Limits" || true
  sleep 1
fi

"$SRC/build.sh" "$APP"
open "$APP"

cat <<DONE

Limits is running. Look for it in the menu bar, near the clock.

macOS will ask once to allow notifications, and may ask once for access to the
Claude Code keychain item; choose Always Allow so it can read usage unattended.

Start it automatically at login from Settings inside the panel.
DONE
