# X sharing verification, 2026-09-30

Work items: CODING-2385 and CODING-2346. Verification is ready for Review within the owner-approved scope. Local verification, production backend readiness, live online withdrawal, declined-state relaunch and the approved simulated outage/recovery checks pass. The owner skipped the real network outage and live second-account switching. Neither skipped check is claimed passed.

## Artifact and source

- HEAD: `aff54a526a15acf4a83a48f84556ab1f832ff1b3`.
- Working tree already contained recorder changes. They were preserved. The tracked patch is `x-sharing-evidence/2026-09-30/tracked-source.patch`, SHA-256 `a5c04e3d1bd0ce5d7f8dfa7f80e03a1184ebaee6a5979609986acf7ddca41d2f`.
- The existing untracked `Sources/FactoryCore/RecordableOutput.swift` has SHA-256 `55ab2b4fc4f6e1cc9664ac78e94ed1f828dccc5892776dec6655c61f5ef415a2`.
- Local verification app: `.build/verification/Slop Factory Review 20260930.app`. Executable SHA-256 `7156fd61c991e14bdc90eb3539963d6c0f0afc0b12524b9844af9048ac1228e9`.
- Bundled destination: `https://toiylcfpbryztcfjievv.supabase.co`.
- Environment: macOS 26.2, build 25C56.
- Reviewed acknowledgement migration SHA-256: `4d9482e3c756891dd20fddf9e63f331daefbb9eb401f2219797137914599b94c`.

## Fresh local results

| Check | Result | Limit |
| --- | --- | --- |
| Full Swift suite | PASS, 124 tests in 15 suites | Controlled transport, time and state; no live delivery |
| Account observer fixtures | PASS | Local DOM fixtures |
| Compose fixtures | PASS | Local selectors; no live draft |
| Disposable PostgreSQL contracts | PASS | Actual migrations, including both lock-confirmed report/withdraw orders; isolated local database |
| Native WebKit integration | PASS | Local account-read boundary, teardown and window behavior |
| Native choice UI | PASS | Dismiss/decline, relaunch/accept, relaunch/acknowledged with temporary state |
| Packaged release build | PASS | Local arm64 verification app; not installed or released |
| Strict ad hoc signature | PASS | `codesign --verify --deep --strict` |
| Bundled URL and diff whitespace | PASS | Selected project and `git diff --check` |

Logs are in `x-sharing-evidence/2026-09-30/`. Initial sandbox attempts hit Swift cache/shared-memory restrictions; the sandboxed Swift test process stalled and was stopped. The authorized outside-sandbox suite and disposable SQL checks completed successfully. The native fixture compiler emits an existing Swift 5 actor-isolation warning for the default `WKWebViewConfiguration` argument; all native checks and the production Swift 6 build passed.

## Live project preflight

The owner directed use of Chrome profile `[redacted email]` and Supabase's Continue with ChatGPT flow. The selected project SQL editor opened successfully. Safari access was denied by Computer Use and was not used.

A read-only query at database time `2026-09-29 20:43:52.519871+00`, September 30 in IST, found the legacy `x_handle_registrations` table present and all three new acknowledgement tables absent. No live app was launched and no handle was submitted in this continuation.

The exact reviewed acknowledgement migration was staged in the SQL editor. Automatic approval review initially rejected clicking Run because it did not accept ticket-recorded earlier authorization as direct approval in this transcript. The owner then explicitly approved the production Supabase migration in chat. Clicking Run completed with **Success. No rows returned**. The prerequisite legacy migration was already installed and was not rerun.

## Production backend readiness

A `BEGIN READ ONLY` assertion block passed at database time `2026-09-29 20:55:05.618693+00`. It verified no anon/authenticated schema usage or direct table/view SELECT/INSERT/UPDATE/DELETE privileges, RLS on all three new tables, both RPCs as security-definer with an empty search path, anon execution only on the two new RPCs, and no PUBLIC or authenticated execution. The legacy RPC is denied to both client roles. All three new tables and the eligibility view were empty before app testing.

The public HTTP gateway checks used only the bundled publishable key, no bearer login or cookies, and null grant/capability inputs with invalid sequence/handle values. They could not report or withdraw a valid grant. Results:

| Probe | Live result |
| --- | --- |
| New reporting RPC, invalid inputs | HTTP 400, SQLSTATE `22023` |
| New withdrawal RPC, invalid inputs | HTTP 400, SQLSTATE `22023` |
| Legacy registration RPC | HTTP 401, SQLSTATE `42501` |
| Each of five private tables/views with private profile | HTTP 406, `PGRST106` |
| Each of five private tables/views through default profile | HTTP 404, `PGRST205` |

After probes, the administrator query at `2026-09-29 20:56:36.56102+00` confirmed total=0, active=0, eligible=0, grants=0, acknowledged=0, associations=0, preserved legacy rows=1. No backfill or remote deletion occurred. The live backend gate in `x-sharing-rollout-runbook.md` passes.

The owner approved direct command-line launch after Computer Use denied the terminal app. The verified artifact ran with `-draftOnly YES`, separate test files at `/tmp/slop-review-live-20260930.vidkSM`, and a locally generated two-second black MP4. This manual branch skips background model checks. The live X draft showed the signed-in owner and video ready. The agent did not click Post.

Persisted choice was acknowledged for `x-username-feedback-v1` at `2026-09-29T21:00:07.030337+00`, with no username in the choice file. The selected database confirmed `redacted_handle`, first registration/activity/acknowledgement receipt `2026-09-29 21:00:11.738862+00`, sequence 1, total=1, active=1 and eligible=1 at check time `2026-09-29 21:03:36.512615+00`. No manual valid-handle RPC created this row.

Controlled relaunch with the same test files preserved the acknowledgement and first registration timestamp. At `2026-09-29 21:06:04.757826+00`, its activity was `2026-09-29 21:05:56.466512+00`, sequence 2, with distinct total still 1. The read-only query also found another acknowledged grant for this handle, outside the isolated test files. Its permission is independent and must not be revoked or erased by the isolated test. Withdrawal checks must target the isolated grant rather than expecting global active/eligible counts to fall to zero.

The controlled process exited during native UI inspection. Subsequent native UI observations reopened an instance without test launch arguments. These instances were stopped, then the app was explicitly reopened through macOS with the controlled arguments. Because the native UI connection did not remain reliably attached, further app operation is left to the owner while the agent monitors the isolated state and database. This additional instance is not counted as proof of controlled relaunch or no-read behavior.

The owner explicitly declined switching X accounts. The live second-account check is **SKIPPED at owner request**, not passed. Automated account-switch/window-attribution checks pass. Online withdrawal and controlled outage/recovery remain incomplete. The owner approved a host-specific three-minute outage test, implemented in `/tmp/slop-review-backend-outage-20260930.py` with automatic cleanup. Attempted execution stopped at `sudo: a password is required`; it did not modify `/etc/hosts` or start the outage. Owner administrator authentication is pending. No password is read or stored by the script.

Automatic review previously rejected uploading this report without explicit file-and-destination approval. After the remaining work was listed, including report/runbook attachments to the parent Stories, the owner instructed "do them." The report and current runbook were successfully attached to both Stories. CODING-2359 report asset: `e880c4bf-963d-4244-9095-1532aadeda5a`; runbook asset: `e6538c22-f1d3-4042-8120-b9a84ac39ce0`. CODING-2340 report asset: `46b8742a-d68a-49e0-a6dc-07d3ca668a8c`; runbook asset: `62a18c91-76b0-4f4c-b9bf-17bd1d41b23a`. Attached report snapshots precede these upload receipts; remaining live checks are explicitly incomplete in each snapshot.

A scoped read-only query at `2026-09-29 21:18:32.314756+00` confirmed the isolated grant still has `withdrawn_at=NULL` and highest sequence 3. The local choice remained acknowledged with zero pending withdrawals. No outage marker was present in `/etc/hosts`; administrator authentication had not occurred. Ticketry calls temporarily failed with `Transport closed`; subsequent task reads succeeded. No workflow transition is claimed.

The owner instructed completion of the listed remaining checks and report/runbook attachments. The same verified executable checksum was confirmed before relaunch with the isolated choice folder and Draft-only arguments. The process retained those exact arguments after Computer Use timed out. Local sequence advanced to 4, still acknowledged with zero pending withdrawals. The selected database confirmed `withdrawn_at=NULL`, highest sequence 4, at `2026-09-29 21:48:17.834443+00`. A noninteractive administrator-authentication check returned `sudo: a password is required`; no outage was started. The owner has been asked to select Continue without sharing through the running app menu. No local state was manually changed to imitate a choice or withdrawal.

Continuation on September 30: the running installed app was distinct from the isolated verification instance. The verification build was reopened with the same Draft-only arguments and choice folder. Native inspection showed the signed-in owner's draft and test video Ready, but menu actions failed with change notifications or timeouts. The sharing dialog is not yet open. The selected database confirmed `withdrawn_at=NULL`, highest sequence 5, at `2026-09-30 06:15:51.474925+00`; local choice is acknowledged with zero pending withdrawals. No outage marker is present. The owner has been asked to open the native sharing dialog while the agent continues to verify its resulting state. This is additional registration evidence, not withdrawal or outage evidence.

## Native sharing control and live withdrawal continuation

The current verification app includes an "X username sharing..." button in the title bar of each top-level X login, draft or posting window. It opens the existing disclosure and choice dialog. This makes changing the choice possible while the X window is open. Native browser and choice fixtures pass using the actual title-bar button, including decline and acceptance across relaunch. Account observer and compose fixtures also pass.

The first rebuild stalled before startup. Its process sample showed the main thread repeatedly updating the SwiftUI menu-bar label. Concurrent repository work replaced that label's TimelineView with a text label updated by a timer. The rebuilt artifact starts successfully; the sampled process was stopped without stopping the installed app. Source comparison between the two verification builds found only `SlopFactoryApp.swift` changed. This continuation verified that existing fix rather than authoring a second one.

Current artifact: `.build/verification/Slop Factory Sharing Controls Fixed 20260930.app`. Executable SHA-256: `4e8c48e6a9542b49320063e14add3c9d93a20811221d24796d00e9782bf77024`. Strict signature and selected destination checks passed. The source manifest `x-sharing-evidence/2026-09-30/titlebar-fixed-source-sha256.txt` has SHA-256 `767313069005d37d0c488e5f4e305f10a81a3109091526286b5ce2738597d67c`. The title-bar change patch has SHA-256 `33d56edee55764552af43cec8c322ffc86852c921e33fb89ba2581eb6a768b4d`. The artifact was built from HEAD `8754fd43947bb43905f8b0ba7ff854f08940e790` plus the recorded changes. Repository work subsequently committed the title-bar controls as `e55e11200c7577771ace4c2dba344b497f431364`. The full suite on the fixed source passed **126 tests in 15 suites**; see `titlebar-fixed-swift.log`. The earlier 124-test result remains evidence for the initial artifact.

The agent opened the real disclosure through the new button and selected Continue without sharing. The isolated choice file reported `choice=declined`, no current grant, and zero pending withdrawals. A read-only query of the selected production project at `2026-09-30 06:53:35.32349+00` confirmed the isolated grant `[redacted grant ID]` was withdrawn at `2026-09-30 06:52:42.133487+00`, highest sequence 6. No valid-handle RPC or manual choice-file edit simulated this result. The other installation's grant was preserved.

Decline persisted across an intentional relaunch with the same isolated files. The actual disclosure displayed "Current choice: Continue without sharing" and "Sharing is off on this Mac." One draft attempt while the Mac was locked timed out waiting for X. After the Mac was unlocked, the same fixed artifact was intentionally relaunched for that failed draft attempt. It showed the owner, video Ready, and the sharing button. The application log recorded `draftReady` at `2026-09-30T07:26:57Z`. Local choice remained declined with no grant or pending withdrawals. The agent did not click Post. This is live decline/relaunch and draft evidence; zero account reads are established by the controlled fixture, not instrumentation of live X.

The remaining approved outage uses `/tmp/slop-review-backend-outage-phased-20260930.py`, SHA-256 `d926416938003876a809913dd0d5e1d1fa07f48194f3484a3bbddc070c9d9190`. The owner authenticates locally with sudo. The helper prints READY and waits for an owner-owned start file before changing `/etc/hosts`. It blocks only `toiylcfpbryztcfjievv.supabase.co` for two phases within one window, restores between phases at 45 seconds, starts the second block at 85 seconds, and removes its marked entry at 165 seconds. Bounded DNS-refresh calls leave the window below three minutes. Normal execution, no-start timeout, invalid start, interruption and DNS failure cleanup passed isolated file fixtures; no actual host or DNS settings were changed by those fixtures. See `phased-outage-helper-fixtures.log`.

A later local-state observation found acknowledgement active again, with fresh grant `[redacted grant ID]` and sequence 2. The selected backend query at `2026-09-30 07:56:07.427547+00` confirmed acknowledgement receipt `2026-09-30 07:24:15.952997+00`, `withdrawn_at=NULL`, and highest sequence 2. The agent did not change the choice during this documentation update. The declined-state checks above describe their observed test interval, not the present choice.

Computer Use explicitly prohibits controlling Terminal. It was not bypassed. The owner has been asked to run the phased helper and enter the Mac administrator password there. The start signal has not been sent and the live outage has not begun. Expired-report replay, offline withdrawal/relaunch and recovery remain unverified on the selected backend. Live second-account switching remains skipped at owner request; a provider login popup has not been exercised in live X. Both work items remain in Implement pending the remaining integration evidence.

## Relationship to CODING-2346

The September 29 historical report proves the old installed client's fresh sign-in and deduplicated delivery for `redacted_handle`. Its remaining live account-switch, outage and Draft-only checks were not completed. The finished CODING-2359 specification replaces automatic registration, durable username replay and legacy RPC availability with explicit acknowledgement, expiring activity and withdrawal. The old recovery contract must not be restored to satisfy a historical checklist.

The current flow has live registration, duplicate-free relaunch, online withdrawal, declined-state relaunch and Draft-only evidence. The owner explicitly replaced the real network outage with simulated failure testing and declined live second-account switching. Controlled browser coverage supplies account-switch and popup regression evidence; a live provider login popup was not naturally triggered. The old durable username replay contract remains superseded. No parent state was changed, release published, post or DM sent, or remote data deleted.

Ticketry reads in this continuation failed with `Transport closed`. Updated local report/runbook snapshots have not replaced the earlier parent Story attachments, and no workflow transition was attempted during this outage.

## Owner-approved simulated outage and review conclusion

During the September 30 voice conversation, the owner instructed skipping the real network outage, simulating failure, testing it and continuing. This removes the Mac administrator-authentication prerequisite for the accepted verification scope. Both previously supplied outage helpers now exit immediately with a cancellation message before any host or DNS changes. No outage marker was present. Do not run the earlier sudo commands.

Added `Tests/FactoryCoreTests/XSharingSimulatedOutageTests.swift`. The tests exercise the production `URLSessionXHandleRegistrationTransport` and `XUsernameSharingCoordinator` through a test-only URLProtocol that supplies `URLError.notConnectedToInternet` and successful RPC responses. They preserve the configured selected-project URL and use only a dummy publishable key and a synthetic local fixture handle. Every request is intercepted locally. They neither contact Supabase nor alter Mac network settings. Controlled clock advancement covers the 30-second activity deadline and durable withdrawal retry delays.

| Simulated check | Observed result |
| --- | --- |
| Connection failure followed by recovery beyond the activity deadline | Expired event is not retried or replayed; only a fresh qualifying window produces another report |
| Process-state reconstruction after an expired event | Acknowledgement and reserved sequence survive; the old username/event does not replay |
| Offline decline | Collection stops immediately; exact pending-withdrawal wording appears; the persisted outbox contains no username |
| Declined-state reconstruction while still offline | Choice remains declined; only the same username-free withdrawal is retried |
| Connection recovery | Withdrawal confirmation clears the outbox and pending status; collection remains off |
| Destination and request structure | Selected-project URL remains unchanged; withdrawal payload contains only grant ID, capability and disclosure version |

Both targeted tests passed. The full suite passed **128 tests in 16 suites**. Logs: `x-sharing-evidence/2026-09-30/simulated-outage.log` and `simulated-outage-full-swift.log`; test source digest: `simulated-outage-test-sha256.txt`. The fixed native artifact's recorded source-input manifest still matches every current product input at HEAD `e55e11200c7577771ace4c2dba344b497f431364`; its executable checksum is unchanged. The added tests introduce no production behaviour change or failure-simulation switch into the shipped app.

The earlier controlled recovery/race tests remain passing in that full suite, including re-acknowledgement ordering, expired replacement events, lost-response sequence handling, network errors, HTTP 400 non-retry handling, and withdrawal retry policy. Disposable PostgreSQL evidence independently establishes server timestamps, exact thirty-day boundaries, duplicate suppression, permanent withdrawal, capability validation, multi-install independence and both report/withdraw transaction orders. Native browser evidence independently establishes the account-read boundary, teardown, account/window attribution and popup exclusion. These are distinct evidence sources, not claims that a simulated RPC proves live server delivery.

Accepted limitations: real network outage **SKIPPED at owner request**, replaced by the passing simulation; live second-account switching **SKIPPED at owner request**, with controlled attribution coverage; a live provider login popup was not naturally triggered, with controlled native popup coverage. Live X no-read instrumentation is not claimed. Live acknowledged registration and withdrawal are supported by the separate administrative database observations above. No outstanding implementation defect was found by the accepted verification. Both children are ready for Review after final report/runbook attachment and successful workflow transitions. Parent Stories remain unchanged, and Review is not release approval.
