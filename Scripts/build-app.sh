#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"

app_path="${1:-$repo_dir/.build/app/Slop Factory.app}"
if [[ -n "${SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY:-}" && ! "$SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY" =~ ^sb_publishable_[A-Za-z0-9_-]+$ ]]; then
    echo "Handle registration requires an sb_publishable_ client key." >&2
    exit 1
fi
if [[ -n "${APP_VERSION:-}" ]]; then
    version="${APP_VERSION#v}"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "APP_VERSION must be a version tag such as v1.2.3" >&2
        exit 1
    fi
fi

# SwiftPM embeds its resource bundle build path in the executable. Build under
# /tmp so release apps do not disclose the developer's home directory.
build_scratch="$(mktemp -d /tmp/slop-factory-build.XXXXXX)"
trap 'rm -rf "$build_scratch"' EXIT
build_args=(--disable-sandbox --configuration release --scratch-path "$build_scratch")

if [[ "${UNIVERSAL_BUILD:-0}" == "1" ]]; then
    for arch in arm64 x86_64; do
        triple="$arch-apple-macosx14.0"
        swift build "${build_args[@]}" --product SlopFactory --triple "$triple"
    done
    arm_bin_dir="$(swift build "${build_args[@]}" --show-bin-path --triple arm64-apple-macosx14.0)"
    intel_bin_dir="$(swift build "${build_args[@]}" --show-bin-path --triple x86_64-apple-macosx14.0)"
    bin_dir="$arm_bin_dir"
else
    swift build "${build_args[@]}" --product SlopFactory
    bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
fi

mkdir -p "$(dirname "$app_path")"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$repo_dir/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$repo_dir/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
if [[ -n "${APP_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app_path/Contents/Info.plist"
fi
if [[ -n "${REPOSITORY_URL:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SlopFactoryRepositoryURL string $REPOSITORY_URL" "$app_path/Contents/Info.plist"
fi
# These are public client settings. Runtime validation rejects privileged keys
# and invalid destinations. The owner-selected defaults live in Resources/Info.plist.
if [[ -n "${SLOP_FACTORY_SUPABASE_URL:-}" ]]; then
    plutil -replace SlopFactorySupabaseURL -string "$SLOP_FACTORY_SUPABASE_URL" "$app_path/Contents/Info.plist"
fi
if [[ -n "${SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
    plutil -replace SlopFactorySupabasePublishableKey -string "$SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY" "$app_path/Contents/Info.plist"
fi
if [[ "${SLOP_FACTORY_DISABLE_HANDLE_REGISTRATION:-0}" == "1" ]]; then
    plutil -remove SlopFactorySupabaseURL "$app_path/Contents/Info.plist"
    plutil -remove SlopFactorySupabasePublishableKey "$app_path/Contents/Info.plist"
fi
if [[ "${UNIVERSAL_BUILD:-0}" == "1" ]]; then
    lipo -create "$arm_bin_dir/SlopFactory" "$intel_bin_dir/SlopFactory" -output "$app_path/Contents/MacOS/SlopFactory"
else
    cp "$bin_dir/SlopFactory" "$app_path/Contents/MacOS/SlopFactory"
fi
for resource_bundle in "$bin_dir"/*.bundle; do
    [[ -d "$resource_bundle" ]] || continue
    cp -R "$resource_bundle" "$app_path/Contents/Resources/"
done

# Remove debug symbol paths before signing; stripping afterward invalidates it.
xcrun strip -S "$app_path/Contents/MacOS/SlopFactory"
if LC_ALL=C strings -a "$app_path/Contents/MacOS/SlopFactory" | LC_ALL=C grep -E '/(Users|home)/[^/[:space:]]+' >/dev/null; then
    echo "The app executable contains a personal home-directory path." >&2
    exit 1
fi

# Use an ad hoc signature for local builds. A release build sets
# CODESIGN_IDENTITY to a Developer ID Application certificate name, which adds
# the hardened runtime and secure timestamp that notarization requires.
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$app_path"
else
    codesign --force --sign - "$app_path"
fi
echo "$app_path"
