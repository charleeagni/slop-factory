# CODING-2385 native and Swift evidence

Date: 2026-09-29. Source base: `66b6a4de351cb9039d427b395a0415d757247243` plus the combined uncommitted CODING-2383/2384/2385 working tree. Read the complete finished CODING-2359 specification at `spec/slop-factory--c7b4571a/T2359--ask-users-to-acknowledge-x-username-coll/spec.md`.

Environment: macOS 26.2 build 25C56, arm64, Apple Swift 6.2.1, Xcode SDK macOS 26.1, Node v24.21.0. Local evidence logs are in `/tmp/2385-native/`.

## Executed checks

- `CLANG_MODULE_CACHE_PATH=/tmp/2385-native/module-cache swift test --disable-sandbox --scratch-path /tmp/2385-native/approved-build`: 120 tests in 14 suites passed in the final combined run, including the new payload-contract test. Final log `swift-test-final.log`. Earlier baseline log `swift-test-approved.log` recorded 119 tests in 13 suites. Sandbox-only initial execution stalled after test discovery and was stopped after the approved native-service run passed. The initial default compiler cache path was not writable, so subsequent commands used a temporary cache.
- `CLANG_MODULE_CACHE_PATH=/tmp/2385-native/module-cache Scripts/build-app.sh '/tmp/2385-native/Slop Factory.app'`: passed. Release executable SHA-256 `264a05d0ff77120005b94ad222013247e43be0c9cf9b3e22870ef11d7f8ff62e`. `codesign --verify --deep --strict` passed. Log `build.log`. This is a local ad hoc signed arm64 app, not a universal or notarized release.
- `CLANG_MODULE_CACHE_PATH=/tmp/2385-native/module-cache Scripts/test-x-sharing-browser.sh`: passed with approved access to native WebKit services. Log `browser-approved.log`. The standalone Swift 5 fixture compile retains the pre-existing main-actor default argument warning; the Swift 6 native app build passes.
- `git diff --check`: passed.

## What the integrated fixtures prove

The existing WebKit fixture creates local HTML with an X origin, real `XBrowserView` and coordinator, temporary state, and fake reporting transport. It counts actual profile-selector queries in the same isolated JavaScript world used by the observer. The counter stays zero before choice, increases only after acknowledgement, and stops changing after withdrawal, destination change, or invalid configuration. This checks account reads, not merely absence of network traffic.

It checks enabling an already-open signed-in fixture, simultaneous windows, account switching, logout and same-handle rediscovery, provider popup exclusion, queued messages with stale generations or wrong sessions, connected withdrawal, replacement acknowledgement, destination changes and same-destination key rotation. Native window closure retires its session. Menu login close/reopen creates a fresh session. The menu-login fixture invokes the real login constructor and immediately stops loading; it does not sign in, post, or count as live X evidence.

CODING-2385 extends the script with `Tests/XSharingIntegration/Choice/main.swift`. This executable compiles the actual `XHandleRegistrationService`, presents its real NSAlert, and clicks its native buttons with a main-run-loop callback. It checks exact disclosure/scope wording, dismissal leaving unknown and disabled, explicit decline with choice time, decline surviving a new process without another startup prompt, explicit acknowledgement with time, acknowledged relaunch without another startup prompt, and closing review preserving acknowledgement. Each run uses a temporary `--app-data-folder`, fixture destination, and no X window, so these stages make no reporting or withdrawal requests. They do not change the user's app settings.

The Swift suite exercises old pending/delivered queue cleanup, persistence failures, corrupt-state preservation, version and destination changes, monotonic expiry, bounded retry, lost-response sequence reuse, decline and withdrawal recovery, re-acknowledgement ordering, late callback rejection, and ordinary app model/posting core behavior.

## Evidence limits

The packaged app was built and signature-checked but was not launched for an end-to-end live X flow. Native disclosure and WebKit collection were exercised by separate controlled executables compiled from the production source. This does not prove real provider popup behavior, owner-authorized sign-in, real manual/automatic posting windows, or backend readiness. Local compose fixtures and code-path coverage cannot replace those controlled live checks. No post or DM was sent. No live migration or release was performed.
