# X acknowledgement verification, 2026-09-29

Work item CODING-2385, parent Story CODING-2359. Contract: finished specification attachment `1d52f855-344e-4820-ba32-583da97aa40d`. The matching finished local specification was read in full. Earlier draft attachments and legacy registration evidence do not satisfy this feature.

Status: local checks passed; live delivery is not proven. CODING-2385 remains incomplete until the owner-authorized destination and sign-in checks pass. The selected destination is `https://toiylcfpbryztcfjievv.supabase.co`. Selection of this destination and its bundled publishable key does not authorize a new migration or sign-in.

## Revision and environment

The tested working tree is based on `66b6a4de351cb9039d427b395a0415d757247243` with uncommitted CODING-2383 and CODING-2384 implementation and unrelated recorder work. HEAD alone does not identify this build. No commit or release was created by this verification slice.

Environment: macOS 26.2, build 25C56; Swift 6.2.1; Node 24.21.0; PostgreSQL 17.10. Disposable PostgreSQL uses a temporary Unix socket and no TCP listener. Local Swift/WebKit checks use controlled state and transport. Compiler caches, native services, and PostgreSQL shared memory require approved local sandbox escalation.

Local artifact: `/tmp/2385-native/Slop Factory.app`, arm64 release build, ad hoc signed. Executable SHA-256 is `264a05d0ff77120005b94ad222013247e43be0c9cf9b3e22870ef11d7f8ff62e`. It was built and signature-checked, not installed or launched for a live X flow.

The [source manifest](x-sharing-evidence/source-sha256.txt) identifies tracked and untracked source, tests, scripts, resources and backend files. Its SHA-256 is `7e223002e9c505bf12cf8e52ebe4318564bf2baf7df5e8912be6361786ac4560`. The [tracked source patch](x-sharing-evidence/tracked-source.patch) has SHA-256 `5ff56845d7b3c70d38af45940a31de75351eee8ffe5ef52811039c2d56108e69`; it does not contain untracked additions, which are individually identified by the manifest. The additive migration SHA-256 is `4d9482e3c756891dd20fddf9e63f331daefbb9eb401f2219797137914599b94c`.

## Executed checks

All final commands below exited successfully on 2026-09-29. [Native details](x-sharing-evidence/native-detail.md) and [backend details](x-sharing-evidence/backend-detail.md) preserve environment, setup failures, reruns and evidence limits.

| Command | Result | Retained evidence |
| --- | --- | --- |
| `CLANG_MODULE_CACHE_PATH=/tmp/2385-native/module-cache swift test --disable-sandbox --scratch-path /tmp/2385-native/approved-build` | 120 tests in 14 suites passed | [Swift log](x-sharing-evidence/swift.log) |
| `node Scripts/test-x-account-observer.mjs` | Passed | [Observer log](x-sharing-evidence/observer.log) |
| `node Scripts/test-x-compose-dialog.mjs` | Passed | [Compose log](x-sharing-evidence/compose.log) |
| `bash Scripts/test-x-handle-database.sh` | Passed, including initial empty counts and both concurrent orders | [PostgreSQL log](x-sharing-evidence/postgres.log) |
| `CLANG_MODULE_CACHE_PATH=/tmp/2385-native/module-cache Scripts/test-x-sharing-browser.sh` | WebKit and three native dialog process stages passed | [Native browser/dialog log](x-sharing-evidence/native-browser-choice.log) |
| `CLANG_MODULE_CACHE_PATH=/tmp/2385-native/module-cache Scripts/build-app.sh '/tmp/2385-native/Slop Factory.app'` | Packaged successfully | [Build log](x-sharing-evidence/native-build.log) |
| `codesign --verify --deep --strict '/tmp/2385-native/Slop Factory.app'` | Passed | Native details above |
| `git diff --check` | Passed | Checked again after documentation integration |

This slice added three coverage checks without changing production behavior: the real native disclosure and process-relaunch driver; exact report/withdrawal payload, header and private-state assertions; and an explicit empty-registry SQL assertion. The payload test initially had a nested Swift macro compile error, which was corrected before the final full suite passed. No behavioral integration defect was found. These are added verification coverage, not a claimed red/green production fix.

The native dialog driver compiles the actual `XHandleRegistrationService`, clicks real NSAlert buttons and checks exact disclosure and installation-scope wording. It verifies dismissal leaves unknown/off, decline and acknowledgement persist across fresh processes, saved choices do not prompt again at startup, and closing review preserves the choice. It uses temporary app data, fixture configuration and no X windows. The separate WebKit fixture supplies the account-read evidence. Neither is an end-to-end walkthrough of the packaged app against live X.

`XSharingPayloadTests` checks exact RPC key/header allowlists, no Cookie or Authorization header, disabled cookie handling, grant UUID/capability format, 0600 state-file permissions and no observed handle persisted in acknowledged or pending-withdrawal state. Source inspection confirms 32 random capability bytes from `SecRandomCopyBytes`; the format assertion alone is not proof of entropy.

## Evidence matrix

| Requirement | Local evidence and boundary |
| --- | --- |
| Unknown choice and existing signed-in page | Observer fixtures count analytics profile-link DOM queries. Native WebKit loads a local page with an existing account link and asserts zero reads before acknowledgement. This proves more than absence of HTTP traffic; it does not establish current live X markup. |
| Upgrade and old pending/delivered handles | `XSharingPersistenceTests` verifies cleanup and no legacy replay even after later acknowledgement; failed cleanup disables collection. The native launch source calls the sharing gate before manual draft and normal startup paths. |
| Acceptance, decline, relaunch and failed persistence | Coordinator tests cover saved version/time, process restart, fail-closed writes and preserved corrupt withdrawal data. The real native dialog process stages passed as described above. |
| Menu login, account switching, logout and windows | Native WebKit checks cover menu close/reopen, separate window handles, logout/rediscovery suppression, account changes, stale messages, and provider-popup exclusion. These use local pages; live provider sign-in remains pending. |
| Manual draft and ordinary posting | Both construct the same gated `XBrowserView`; startup enters the gate before handling `--draft-video`. Swift model/posting tests and compose selector fixtures pass independently. This is not a completed live posting-window walkthrough. |
| Decline and continued use | WebKit page remains usable after observer shutdown. Existing core/model/posting tests cover normal behavior. Live menu/model/Draft-only use under decline remains an explicit acceptance check. |
| Expiry, lost responses and races | Controlled-clock and transport tests cover monotonic expiry, bounded retry, sequence reservation across restart, account/window invalidation, stale callbacks, and same-destination replacement ordering. SQL covers lost-response duplicates with unchanged timestamps and both lock-confirmed concurrent report/withdrawal orders. |
| Offline withdrawal and recovery | Public coordinator tests check username-free durable outbox, pending status, 1/5/30-minute retry scheduling, permanent errors, configuration repair and confirmation. Native live outage behavior remains pending. |
| Counts and eligibility | Actual disposable migrations/RPCs verify distinct handles, immutable first registration, exact thirty-day boundary, current-version eligibility, multi-install independence and tombstones. Live administrator counts and gateway permissions remain pending. |
| Payloads and private permissions | SQL denies direct client table/view operations and legacy RPC execution. Source uses cookie-free ephemeral networking, no credential storage, and redirect rejection. Exact new-RPC payload assertions passed as described above. |

## Meaning of the results

One acknowledgement covers username recording, handle-based counts and possible feedback DMs. No DM sender is added. Qualifying activity is an acknowledged top-level login or posting window first confirming an account, plus a change to a different account in that window. Reopening counts again. Polling, unchanged navigation, provider popups, passive model checks and retries do not create fresh activity.

Total preserves distinct previously acknowledged handles. Active requires a current-version, non-withdrawn grant with server activity strictly newer than thirty days ago and no later than database time. Handles are client-reported, not verified people; renamed handles can count separately. Offline event loss can undercount both registration and activity. Each installation has an independent grant.

Decline stops local observation immediately. Remote eligibility changes when withdrawal reaches the server; the app shows pending withdrawal until confirmation. Historical delivery acknowledgement from the old registry is not explicit user consent.

## Remaining live checks and operational boundary

Follow [the rollout and rollback runbook](x-sharing-rollout-runbook.md). Before any live action, review the exact additive migration, destination guard, permission/count checks, gateway probes, and Draft-only sign-in matrix there. No legacy backfill, remote deletion, release publication, test post or DM is authorized by this ticket.

The live migration, new RPC gateway behavior, administrator counts, real X sessions, account switching, provider popups, ordinary posting windows and live withdrawal/recovery have not been executed in this run. Earlier owner execution of the old migration does not establish authorization or readiness for this migration. A logged-in dashboard or installed app would not by itself grant that authorization.

Operational blocker: owner authorization and execution/access for the reviewed migration on the selected destination, plus owner-authorized X sign-in and account switching for the controlled Draft-only checks. Supply access through the normal secure session; do not put credentials or grant capabilities in ticket text, attachments, logs or screenshots.

This ticket must remain in Implement while those acceptance checks are blocked. The parent Story must not be advanced manually. The requested `terminate_current_run` call is conditional on a state transition and must not be called before it.


## Owner authorization and access attempt, 2026-09-29

The owner explicitly authorized the reviewed migration on `toiylcfpbryztcfjievv.supabase.co` and Draft-only live checks. This resolves the authorization blocker for that scope; no further release, post, DM or deletion authority is implied. Migration SHA-256 was rechecked and remains `4d9482e3c756891dd20fddf9e63f331daefbb9eb401f2219797137914599b94c`.

Administrative access remains unavailable in this session. Computer Use failed twice with `codex app-server exited before returning a response`. The reviewed `slop_selected_owner` libpq service is not configured and no database connection environment variables are set. A Supabase plugin was found but is not installed/connected; its connection was offered to the owner.

Sandbox API probes could not resolve the selected host. Automatic approval review rejected the outside-sandbox probe because it considered the legacy RPC POST potentially mutating. No successful live response, database migration or app sign-in check resulted. These failures do not establish backend readiness. Continue with the authorized migration once administrative access is available; keep CODING-2385 in Implement.
