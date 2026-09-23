#!/bin/bash
# Regenerates the README images from the current code and your live usage.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p docs
BIN="$(mktemp -d)/shot"
swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  -framework ServiceManagement -framework Security -lsqlite3 \
  -o "$BIN" $(ls Sources/*.swift | grep -v '/main\.swift$') Tools/Shot.swift
"$BIN" docs
