#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --disable-sandbox --product SlopFactory
bin_dir="$(swift build --disable-sandbox --show-bin-path)"
swiftc -swift-version 5 -I "$bin_dir/Modules" Sources/SlopFactory/XBrowserView.swift Sources/SlopFactory/XWebPoster.swift Sources/SlopFactory/XPostLog.swift Sources/SlopFactory/XHandleRegistrationService.swift Tests/XSharingIntegration/main.swift "$bin_dir"/FactoryCore.build/*.o -o "$bin_dir/x-sharing-browser-integration"
"$bin_dir/x-sharing-browser-integration"

# Drive the real native disclosure with temporary choice storage. These stages
# open no X windows and therefore make no reporting or withdrawal requests.
swiftc -swift-version 5 -I "$bin_dir/Modules" Sources/SlopFactory/XBrowserView.swift Sources/SlopFactory/XHandleRegistrationService.swift Tests/XSharingIntegration/Choice/main.swift "$bin_dir"/FactoryCore.build/*.o -o "$bin_dir/x-sharing-choice-integration"
choice_dir="$(mktemp -d)"
trap 'rm -rf "$choice_dir"' EXIT
for mode in dismiss-decline relaunch-accept relaunch-acknowledged; do
    SLOP_FACTORY_SUPABASE_URL=https://example.supabase.co SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY=sb_publishable_fixture \
        "$bin_dir/x-sharing-choice-integration" --app-data-folder "$choice_dir" "$mode"
done
