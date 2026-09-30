# X sharing connected path verification

CODING-2383 implements the connected path from the finished CODING-2359 specification, attachment `1d52f855-344e-4820-ba32-583da97aa40d`. The matching local specification was read in full. This intermediate slice must not be released before CODING-2384 and CODING-2385 complete.

The app now records the combined acknowledgement before browser observation. The menu can review or change it. A new owner-only state file replaces legacy launch replay, reserves report sequences, and stores a username-free withdrawal outbox. Window sessions supply their own account observations. The private SQL registry uses capability hashes, locked sequence deduplication, permanent withdrawal tombstones, and administrator-only distinct counts and feedback eligibility.

Validation on 2026-09-29:

- `swift test --disable-sandbox`: 91 tests across 11 suites passed. Sandbox runs stalled; a clean run outside the sandbox passed.
- `node Scripts/test-x-account-observer.mjs`: passed.
- `node Scripts/test-x-compose-dialog.mjs`: passed.
- `Scripts/test-x-sharing-browser.sh`: passed outside the sandbox, using local HTML, temporary state, the real coordinator and WebKit browser, and a fake transport. It checks no account reads before choice, enabling an existing window, reporting its account, popup exclusion, connected withdrawal, observer shutdown, continued page usability, re-acknowledgement, and native window closure. The Swift 5 fixture compiler emits a main-actor default-argument warning; the app's Swift 6 build succeeds.
- `Scripts/test-x-handle-database.sh`: passed in a disposable PostgreSQL cluster. Includes duplicates, invalid inputs/capabilities, withdrawal before reporting, concurrent reporting/withdrawal, multiple grants per handle, exact 30-day and future boundaries, revoked legacy RPC, and denied client table/view access.
- `CLANG_MODULE_CACHE_PATH=/tmp/slop-sharing-module-cache Scripts/build-app.sh`: packaged and ad hoc signed `.build/app/Slop Factory.app` successfully.
- `git diff --check`: passed.

Recovery work still required in CODING-2384 includes prescribed ordinary-report and withdrawal retry timers, Retry-After handling, exhaustive interruption and stale-response cases, and event coordination while an earlier withdrawal is already running. Basic cancellation and deadline-bounded transport are implemented; the full recovery matrix is not verified. Failed ordinary reports currently drop. Pending withdrawals remain durable and retry on startup or subsequent acknowledged activity.

No live migration, release, X sign-in, post, or DM was performed. Existing recorder work and older verification edits were preserved. Historical registration evidence does not verify this feature or establish acknowledged users.
