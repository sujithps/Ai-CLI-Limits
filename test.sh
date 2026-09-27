#!/bin/bash
# Runs the tests. Extra arguments go to swift test, e.g. --filter Model.
set -euo pipefail
cd "$(dirname "$0")"

# Tools/sdk.sh prints "-sdk <path>" when the default SDK cannot compile
# SwiftUI; swift test spells the same flag with two dashes.
SDK="$(Tools/sdk.sh | sed 's/^-sdk/--sdk/')"

# With the SDK overridden, the first build after an edit sometimes cannot find
# the plugin that expands @Test and @Suite, and the second finds it. Naming the
# directory outright makes every build the second kind.
PLUGINS="$(dirname "$(dirname "$(xcrun -f swiftc)")")/lib/swift/host/plugins/testing"
FLAGS=()
if [ -d "$PLUGINS" ]; then
  FLAGS=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
fi

# $SDK is unquoted on purpose: it is empty or two words.
exec swift test $SDK "${FLAGS[@]}" "$@"
