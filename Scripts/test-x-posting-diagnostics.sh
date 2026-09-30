#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
node Scripts/test-x-posting-alert.mjs
swift build --scratch-path "${SLOP_DIAGNOSTICS_BUILD_DIR:-.build}" --disable-sandbox --product SlopFactory
bin_dir="$(swift build --scratch-path "${SLOP_DIAGNOSTICS_BUILD_DIR:-.build}" --disable-sandbox --show-bin-path)"
swiftc -swift-version 5 -I "$bin_dir/Modules" Sources/SlopFactory/XBrowserView.swift Sources/SlopFactory/XWebPoster.swift Sources/SlopFactory/XPostLog.swift Sources/SlopFactory/XHandleRegistrationService.swift Tests/XPostingDiagnostics/main.swift "$bin_dir"/FactoryCore.build/*.o -o "$bin_dir/x-posting-diagnostics"
choice_dir="$(mktemp -d)"
trap 'rm -rf "$choice_dir"' EXIT
"$bin_dir/x-posting-diagnostics" --app-data-folder "$choice_dir"
