#!/bin/bash
# Regenerates the README images from the current code. Pass --live to use your
# real usage instead of the built-in sample figures.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p docs
BIN="$(mktemp -d)/shot"
swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" $(Tools/sdk.sh) \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  -framework ServiceManagement -framework Security -lsqlite3 \
  -o "$BIN" $(ls Sources/*.swift | grep -v '/main\.swift$') Tools/Shot.swift
"$BIN" docs "$@"
