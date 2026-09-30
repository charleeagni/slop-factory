#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --disable-sandbox --product SlopFactory >/dev/null
bin_dir="$(swift build --disable-sandbox --show-bin-path)"
swiftc -swift-version 6 -I "$bin_dir/Modules" Sources/SlopFactory/WebViewRecorder.swift Tests/RecorderIntegration/main.swift "$bin_dir"/FactoryCore.build/*.o -o "$bin_dir/recorder-integration"
"$bin_dir/recorder-integration" "$PWD/Tests/RecorderIntegration/Fixtures" "${1:-$PWD/.build/recorder-evidence}" "${2:-all}" "${3:-}"
