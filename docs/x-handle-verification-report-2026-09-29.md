> Historical evidence only. This report predates the finished CODING-2359 acknowledgement specification. A server delivery acknowledgement is not user consent. The owner's execution of an older migration does not authorize the new acknowledged-registry migration. Use the [current verification report](x-sharing-verification-2026-09-29.md) and [current rollout and rollback runbook](x-sharing-rollout-runbook.md); their live checks remain subject to the recorded access and sign-in blockers. No legacy row is backfilled or deleted by this work.

# X handle verification report, 2026-09-29

Work item: CODING-2346. Parent: CODING-2340.

Update: the owner subsequently supplied the selected project and publishable key; see the follow-up below. The original preparation record is preserved.

Status at initial preparation: local preparation passed; live verification blocked. Leave CODING-2346 in Implement. The owner has not supplied a selected Supabase test project URL, publishable key, or migration/deployment access. No destination was inferred, configured, or contacted. Owner participation in integrated X sign-in and account switching is still required.

The finished specification was read from parent attachment `c1442f95-0a43-4e7d-b4e0-280f57000216`, revision 2026-09-29. WorkTracker reports prerequisite CODING-2345 resolved. CODING-2346 has no children.

## Revision and artifact

- Integrated code revision: `f71d041e11fe18e7e8c30ed6b0ee28fb14420849`.
- Local artifact: `.build/verification/SlopFactory-CODING-2346.app`, version `0.1.0`, build `1`, ad hoc signed, not launched.
- Executable SHA256: `8b48a0cf83481d09c3c5498fb2779eb5a7790bbb11e1f42bfc724028039e94fd`.
- Migration: `supabase/migrations/20260929000000_register_x_handle.sql`.
- Migration SHA256: `b28c93ce8e92d9326765a0d1fb85bd58eaa62ea6459f2dd257aaca776f933eaa`.
- Environment: macOS 26.2, build 25C56; Swift 6.2.1; Node 24.21.0; PostgreSQL 17.10.
- Destination: not supplied. Both Supabase keys are absent from the built app's Info.plist.

## Checks executed

| Check | Result | Evidence boundary |
| --- | --- | --- |
| `swift test` | PASS, 85 tests across 11 suites | Controlled transport/time and local state; no live Supabase delivery |
| `node Scripts/test-x-account-observer.mjs` | PASS | DOM fixtures; no live X login |
| `node Scripts/test-x-compose-dialog.mjs` | PASS | Compose selector fixtures; no live Draft-only action |
| `Scripts/test-x-handle-database.sh` | PASS | Disposable local PostgreSQL only; no Supabase HTTP gateway |
| Unconfigured app build | PASS | Command below; registration disabled |
| `codesign --verify --deep --strict .build/verification/SlopFactory-CODING-2346.app` | PASS | Local ad hoc signature only |

Compiler cache access and PostgreSQL shared-memory restrictions prevented the initial sandbox attempts. Approved escalated local runs passed. No remote database writes or release publication occurred.

Build command:

```sh
env -u SLOP_FACTORY_SUPABASE_URL -u SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY \
  -u CODESIGN_IDENTITY -u UNIVERSAL_BUILD \
  bash Scripts/build-app.sh .build/verification/SlopFactory-CODING-2346.app
```

## Live checks outstanding

All rows below are NOT RUN, blocked on the selected destination/access and, where needed, owner interaction.

| Check | Required evidence |
| --- | --- |
| Selected test destination and additive migration | Owner selection, project reference, migration result and checksum |
| Configured integrated sign-in | Owner-confirmed observed handle and administrative SQL showing normalized handle and server timestamp |
| Reobservation and relaunch | One row and unchanged first_seen_at after both steps |
| Account switch | Owner-confirmed second account and its separate database row |
| Controlled outage and recovery | Pending record, scheduled retry, successful delivery after restoration, responsive app |
| Client permissions and validation | Gateway denial of registry reads/updates/deletes, invalid submission rejection, repeated RPC success, unchanged row/timestamp |
| Login/provider popup and Draft only | Integrated owner-observed results without publishing a post |

The earlier extraction-only experiment and this run's local tests do not prove live delivery. Follow [the verification runbook](x-handle-live-verification.md) when access arrives and append actual timestamps, results, and evidence to the parent Story.

## Rollout limitations

The audit found no implementation defect requiring a change in this preparation pass. It identified operational details the verification procedure must account for:

- `--app-data-folder` isolates files, but WebKit cookies and app preferences remain shared. A normal launch can run onboarding, login-item registration, and scheduling. Use the existing Draft-only manual launch path for controlled verification.
- Unsetting runtime configuration falls back to bundled settings. Explicit empty runtime values plus a restart disable registration for that process.
- Clearing release Actions variables affects future builds only. Existing installed builds retain their configuration. A server RPC revoke blocks writes but does not stop client collection or remove queued records.
- Live HTTP gateway behavior, actual database delivery, and owner-assisted regression checks remain unverified. No release is authorized by this report.

## Follow-up: owner-selected bundled configuration

The owner supplied project `toiylcfpbryztcfjievv` and its `sb_publishable_` key and requested that the settings be baked into the app. `Resources/Info.plist` now holds those public defaults. Build environment overrides replace them; release Actions variables remain optional overrides. `SLOP_FACTORY_DISABLE_HANDLE_REGISTRATION=1` removes both bundle settings and is also available as a release Actions variable. Clearing the URL/key variables no longer disables the feature because builds retain the bundled defaults.

Built `.build/verification/Slop Factory Configured.app` and checked the exact URL/key and strict ad hoc signature. Built `.build/verification/Slop Factory Disabled.app` and verified both settings are absent and its signature passes. No app launch, sign-in, release publication, or database write was performed.

Two POST probes to the selected project's `/rest/v1/rpc/register_x_handle`, using the supplied publishable key and invalid `p_handle` value `@invalid`, returned HTTP 502 with `{"message":"Bad Gateway"}`. The first response was at 2026-09-29 10:07:57 UTC. This does not establish key validity or migration presence. No valid handle was submitted.

Remaining blockers: selected remote API health, migration/deployment access or owner execution of the reviewed SQL, and owner-assisted integrated login/database evidence. The earlier missing-project/key blocker is resolved. Live acceptance checks remain incomplete and CODING-2346 stays in Implement.

## Live migration and denial verification

The owner ran the staged migration in the selected project's SQL editor. Computer Use confirmed “Success. No rows returned”. An administrative SELECT then confirmed anon RPC execution is true and anon table SELECT, UPDATE, and DELETE privileges are all false. The registry contained zero rows at this check.

Remote RPC probes with null, empty, @invalid, 16-character, reserved home, and non-ASCII café handles all returned HTTP 400, SQLSTATE 22023, Invalid X handle. Gateway GET/PATCH/DELETE probes against the private schema all returned HTTP 406, PGRST106. Only public and graphql_public are exposed; x_handle_registry is not. Write probes filtered an impossible handle and changed no rows.

The previous API-health and migration blockers are resolved. No valid handle has been submitted yet. Integrated owner sign-in, server timestamp, repeat/relaunch/account-switch, outage recovery, and Draft-only/popup live checks remain outstanding. Task stays Implement.

## GitHub DMG installation and first database row

Owner requested a fresh installation from a DMG downloaded from GitHub, superseding the earlier no-release scope. Published v0.1.1 as a prerelease from commit 66b6a4d. GitHub Actions run 36559569398 passed, including 85 Swift tests, universal build, signature verification, and DMG upload. The local observer/compose fixtures also passed before publishing. No signing secrets were configured; the app is ad hoc signed.

Downloaded https://github.com/charleeagni/slop-factory/releases/download/v0.1.1/SlopFactory-v0.1.1-macOS.dmg using gh release download. Download SHA256 matched GitHub: a79f933c3e325556fcc5c7ecf4b39e3ca4f2d73713b012837cefa3263030b90f. Mounted read-only and installed its exact app in /Applications/Slop Factory.app. Version 0.1.1, bundled destination/key verified, strict signature passed. Installed executable SHA256: ca7fa8ebc163103f9b4ea2ae98ca00fb4dc9bd1718aaa906806cda8e03d39a79.

Prior app, Application Support state, WebKit directory, caches, and exported preferences were preserved under ~/Library/Application Support/Slop Factory verification backup 20260929-163620. Draft only was enabled before launch. App data and WebKit directories were absent immediately before first launch.

The owner reported that the app opened already signed in. A separate ~/Library/HTTPStorages/com.slopfactory.app.binarycookies file was subsequently found, so this attempt does not establish a fresh X login. Local delivery state recorded redacted_handle delivered with zero failures. The running executable was confirmed at /Applications/Slop Factory.app/Contents/MacOS/SlopFactory.

Administrative SQL in the selected Supabase dashboard returned exactly one row for redacted_handle, first_seen_at 2026-09-29 11:13:50.289391+00. This proves real installed-app delivery from an existing session. No manual valid-handle RPC was used to create that row. Local acknowledgement file modification was 2026-09-29T11:13:50.366807Z.

Remaining for the active fresh-login goal: quit the app, back up the separately retained cookie file and reset local delivery/onboarding state, relaunch the GitHub DMG installation, owner signs in, then query the database again. The owner also requested “use the same tag”; clarification between v0.1.1 and replacing v0.1.0 is pending. Do not mark the fresh-login goal complete yet.

Fresh-login preparation continued: stopped the exact installed SlopFactory process and preserved the existing-session delivery evidence in the backup's existing-session-verification subdirectory. Moved Application Support state, WebKit data, caches, and the separately retained HTTPStorages/com.slopfactory.app.binarycookies file. Draft only remains enabled. The installed GitHub DMG app is unchanged. Owner login and post-login database query remain pending.

## Fresh login verified

After the cleanup above, confirmed that app data, WebKit data, and the separate cookie file were absent before launching the installed GitHub v0.1.1 app. The owner then confirmed, "I logged in again" and "that was a fresh login".

The newly created x-handle-registrations.json was modified at 2026-09-29 16:58:22 +0530 and contains redacted_handle for https://toiylcfpbryztcfjievv.supabase.co with delivered=true, failures=0, paused=false. This acknowledgement came from fresh local state.

After that confirmation, reran the administrative query in the selected project's Supabase SQL editor:

```sql
SELECT handle, first_seen_at, count(*) OVER () AS matching_rows
FROM x_handle_registry.x_handle_registrations
WHERE handle = 'redacted_handle';
```

It returned redacted_handle, first_seen_at 2026-09-29 11:13:50.289391+00, matching_rows 1. The successful fresh-login delivery preserved the original server timestamp and created no duplicate. No manual valid-handle submission or test post was used.

The owner's fresh-install, login, and database-verification goal is complete. The broader CODING-2346 task remains in Implement pending account-switch, controlled-outage recovery, and the remaining live popup/Draft-only regression checks. The installed artifact remains v0.1.1; no existing release tag was replaced.
