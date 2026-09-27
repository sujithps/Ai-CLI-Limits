#!/bin/bash
# Prints the -sdk flag to compile SwiftUI with, or nothing if the default works.
#
# The macOS 27 command line tools ship a SwiftUI whose property wrappers are
# macros, but not the plugin that expands them, so anything with @State fails
# against the default SDK. The older SDKs still sit beside it, so fall back to
# the newest one that compiles.
set -euo pipefail
probe="$(mktemp -d)"
cat > "$probe/p.swift" <<'SWIFT'
import SwiftUI
struct P: View { @State var n = 0; var body: some View { Text("\(n)") } }
SWIFT
try() {
  swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" "$@" \
    -parse-as-library -emit-object -o "$probe/p.o" "$probe/p.swift" >/dev/null 2>&1
}
if try; then exit 0; fi
for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.*.sdk 2>/dev/null | sort -r); do
  if try -sdk "$sdk"; then
    echo "The default SDK cannot compile SwiftUI; using $(basename "$sdk")." >&2
    echo "-sdk $sdk"
    exit 0
  fi
done
echo "No installed SDK can compile SwiftUI. Install Xcode, or an older command line tools package." >&2
exit 1
