# X sharing recovery verification, 2026-09-29

Work item: CODING-2384. Contract: CODING-2359 finished specification, attachment `1d52f855-344e-4820-ba32-583da97aa40d`.

## Implementation

Ordinary reports have one in-flight request per grant, a monotonic 30-second lifetime, and at most one retry for network errors, HTTP 408/429, or 5xx. Retries preserve the reserved sequence. The five-second retry delay can increase for Retry-After only within the original deadline; each request gets at most 15 seconds and no more than the remaining lifetime.

The separate username-free withdrawal outbox attempts immediately, then after one minute, five minutes, and every 30 minutes. Longer valid Retry-After values delay withdrawal. Permanent client errors remain pending and get a further attempt on a later launch or relevant configuration repair. A replacement grant waits only for withdrawals at its destination. An old grant's delayed reply cannot disable or block the replacement.

Choice changes stop collection before saving. Decline and withdrawal state save together. Save errors remain visible and do not claim that an unsaved preference survives restart. Corrupt state is preserved, including malformed withdrawal metadata. Startup never loads legacy usernames; cleanup failures disable sharing. Reserved report sequences survive interruption and are not reused.

Destination or disclosure changes require a new choice and withdraw the original grant using its own configuration. Key rotation at the same destination preserves the choice. Browser sessions reject stale observations and retain per-window account associations. Closing and reopening menu login now creates a fresh browser session. The menu observes asynchronous status changes directly, including pending remote withdrawal.

## Regression evidence

- Ordinary retry and withdrawal scheduling tests failed before their implementations.
- A malformed negative withdrawal retry count initially allowed acknowledgement to overwrite corrupt state. The regression now verifies fail-closed behavior and byte-for-byte preservation.
- Reopening menu login initially reused the closed window and retired observer session. The native regression failed before the fix and passed after the window owner began clearing the closed login window.
- Configuration regressions reproduced an old-key response suppressing a repaired-key retry, a failed destination-change save losing old-grant withdrawal, and a failed key-repair save suppressing the next repair attempt. Each uses the public coordinator with suspended transport or temporary storage failure.
- SQL tests hold the first transaction open until the second is demonstrably blocked. Both report-first and withdrawal-first orders preserve irreversible withdrawal. A temporary incorrect time-boundary mutation was rejected by the tests and restored before the passing run.

## Completed checks

| Check | Result |
| --- | --- |
| `swift test --disable-sandbox --scratch-path /tmp/sharing-recovery-root` | 119 tests in 13 suites passed, including existing model and posting/core checks |
| `node Scripts/test-x-account-observer.mjs` | Passed |
| `node Scripts/test-x-compose-dialog.mjs` | Passed |
| `Scripts/test-x-sharing-browser.sh` | Native WebKit integration passed |
| `Scripts/test-x-handle-database.sh` | Disposable PostgreSQL contract and both controlled concurrent orders passed |
| `Scripts/build-app.sh` | Native app packaged and ad hoc signed at `.build/app/Slop Factory.app` |
| `git diff --check` | Passed |

Swift compiler caches, WebKit native services, and PostgreSQL shared memory required approved sandbox escalation. The standalone browser fixture emits a Swift 5 actor-isolation warning for its existing WebKit default argument; the Swift 6 app build succeeds.

## Validation scope

Coordinator tests use controlled transport, monotonic and wall clocks, and temporary files. They inspect public choices, request payloads, persisted state, and status. Native WebKit fixtures use local HTML and fake reporting transport for observer teardown, multiple windows, account switching, logout/rediscovery, popups, configuration changes, and stale bridge messages. They also exercise menu login close/reopen without sign-in or posting.

Disposable PostgreSQL tests execute the actual migrations and RPCs. They cover independent installation grants sharing one handle, lost responses, duplicate and skipped sequences, historical total preservation, current-version filtering, exact time boundaries, tombstones, private tables, and legacy exclusion. A transaction-local successor reporting version verifies that supported older grants can still withdraw; it does not add a production disclosure version.

No live migration, release, sign-in, post, or DM was performed. Native browser fixtures do not establish live X behavior or production backend readiness. Final integrated verification and rollout remain CODING-2385's scope. Unrelated recorder work is preserved.
