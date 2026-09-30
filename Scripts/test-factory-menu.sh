#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="${SLOP_MENU_BUILD_DIR:-.build/menu-integration}"
swift build --scratch-path "$scratch" --disable-sandbox --product SlopFactory
bin_dir="$(swift build --scratch-path "$scratch" --disable-sandbox --show-bin-path)"
swiftc -swift-version 6 -I "$bin_dir/Modules" Sources/SlopFactory/FactoryStatusMenu.swift \
    Tests/FactoryMenuIntegration/main.swift "$bin_dir"/FactoryCore.build/*.o \
    -o "$bin_dir/factory-menu-integration"
"$bin_dir/factory-menu-integration"
