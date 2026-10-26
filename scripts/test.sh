#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift_compiler="$(xcrun --find swiftc)"
testing_plugin="${swift_compiler:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
# The Command Line Tools include Swift Testing but some releases omit its macro search path.
if [[ -f "$testing_plugin" ]]; then
    swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$testing_plugin"
else
    swift test --disable-xctest
fi
