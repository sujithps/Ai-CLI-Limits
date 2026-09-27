#!/bin/bash
# Regenerates Resources/AppIcon.icns from Tools/Icon.swift.
set -euo pipefail
cd "$(dirname "$0")"
BIN="$(mktemp -d)/icon"
swiftc -swift-version 5 -framework AppKit -o "$BIN" Tools/Icon.swift
"$BIN" Resources
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
rm -rf Resources/AppIcon.iconset
echo "wrote Resources/AppIcon.icns"
