# X username sharing rollout and rollback

Prepared for CODING-2385 and parent CODING-2359 on 2026-09-29. Authority is finished specification attachment `1d52f855-344e-4820-ba32-583da97aa40d`, reproduced in `spec/slop-factory--c7b4571a/T2359--ask-users-to-acknowledge-x-username-coll/spec.md`.

Update, 2026-09-30: the owner explicitly approved the production migration in chat. The reviewed additive migration completed on the selected project; read-only administrative assertions, initially empty acknowledged counts, both new RPC validation probes, private relation gateway denial and old RPC rejection passed. The legacy row was preserved. See [the September 30 verification report](x-sharing-verification-2026-09-30.md). Live registration, duplicate-free relaunch, withdrawal, declined-state relaunch and Draft-only preparation pass. The owner replaced the real network outage with simulated failure verification, which passes. Remaining live limits are recorded below. Do not rerun the migration; the preparation record below describes its original unexecuted state.

The backend rollout and live acknowledged registration have executed on the selected project. Online withdrawal and declined-state relaunch pass. Simulated connection-failure expiry, withdrawal and recovery pass. The real network outage was skipped at owner request. The only destination for this procedure is `https://toiylcfpbryztcfjievv.supabase.co`, project `toiylcfpbryztcfjievv`. Do not substitute another project, infer migration permission from a bundled publishable key, or publish a release. The owner declined live account switching; record that check as skipped and retain the automated attribution evidence.

## Evidence and prerequisites

The [current verification report](x-sharing-verification-2026-09-30.md) records executed checks and concrete blockers. The [September 29 report](x-sharing-verification-2026-09-29.md) is historical. Complete local verification first. Record `git rev-parse HEAD`, `git status --short`, macOS and Swift versions, UTC check times, command outputs and exit status, and the executable and migration SHA-256 values. A dirty working tree requires a source snapshot or patch digest as well as HEAD. Run:

```sh
swift test
node Scripts/test-x-account-observer.mjs
node Scripts/test-x-compose-dialog.mjs
Scripts/test-x-sharing-browser.sh
Scripts/test-x-handle-database.sh
Scripts/build-app.sh '.build/app/Slop Factory Verification.app'
shasum -a 256 supabase/migrations/*.sql
shasum -a 256 '.build/app/Slop Factory Verification.app/Contents/MacOS/SlopFactory'
```

The PostgreSQL script creates a disposable local database; never run its fixture SQL on the live project. Controlled browser checks establish the account-read boundary, including an already-open window. Local test passes do not prove a live gateway, signed-in X behavior, or deployment.

The owner approved and executed the reviewed acknowledgement migration, and the selected project and signed-in X session are established. The owner enters any remaining administrator password or MFA. The owner skipped the host-specific real outage and approved simulated failure testing instead; no Mac administrator authentication is needed for that accepted scope. The verified fixed artifact starts and exposes a native sharing button in each X window. Online withdrawal, declined-state relaunch and Draft-only preparation pass. Both previously supplied outage helpers have been disabled before network changes. The production network client and coordinator pass simulated connection-failure, expiry, persisted withdrawal and recovery tests. Both children are ready for Review with the stated live limitations; do not claim that a simulated response proves production delivery.

| Live evidence | Status on 2026-09-30 |
| --- | --- |
| Authorized operator, UTC window, project confirmation | PASS, recorded in current report |
| Migration execution, exact checksum, backend permission checks | PASS; do not rerun migration |
| Initially empty acknowledged registry and both RPC gateway checks | PASS before app testing |
| Built artifact hash, source snapshot, signing identity | PASS; controlled app launched with isolated choice state |
| Signed-in owner and manual Draft-only window | Observed; agent did not click Post |
| Live account switching | SKIPPED at owner request; automated attribution coverage passed |
| Live decline, relaunch and Draft-only preparation | PASS on the fixed artifact; local no-read instrumentation passed separately |
| Provider login popup | Not exercised in live X; controlled native coverage passed |
| Acknowledged registration and duplicate-free relaunch | PASS against selected backend |
| Online withdrawal against selected backend | PASS; isolated grant withdrawn at 2026-09-30 06:52:42.133487+00 |
| Simulated outage, expiry, withdrawal and recovery | PASS through production URLSession transport with intercepted connection failures; 128 tests in 16 suites pass |
| Real network outage | SKIPPED at owner request; do not run the cancelled sudo helpers |
| Release publication, test posts, DMs, remote deletion | Outside scope; do not perform |

Attach redacted results and limitations to CODING-2359. Do not attach complete state files, capabilities, request authorization headers, browser cookies, passwords, login tokens, or contact-list exports.

## Backend first

1. Confirm the selected project reference in the administrative console and connection. Review migration history and object definitions before applying anything. `20260929000000_register_x_handle.sql` is a prerequisite; if already present, verify it instead of rerunning it. If neither migration exists, execute the reviewed prerequisite and immediately execute `20260929010000_acknowledged_x_activity.sql` in the same maintenance window, before any client installation. Neither file is an idempotent reapply script. A conflicting or partially applied schema requires investigation.
2. Apply the exact reviewed additive migration `supabase/migrations/20260929010000_acknowledged_x_activity.sql`, SHA-256 `4d9482e3c756891dd20fddf9e63f331daefbb9eb401f2219797137914599b94c`, once using the owner's migration tooling. Its transaction creates the new tables, views and RPCs and revokes old RPC access together. Record operator, UTC start/end, checksum, migration-history entry and success. Do not backfill from or delete `x_handle_registrations`. Historical upload acknowledgements are delivery receipts, never user consent.
   For an owner-configured libpq service named `slop_selected_owner`, whose connection has been independently confirmed as project `toiylcfpbryztcfjievv`, the exact additive migration command is:

   ```sh
   PGSERVICE=slop_selected_owner psql -X -v ON_ERROR_STOP=1 \
     -f supabase/migrations/20260929010000_acknowledged_x_activity.sql
   ```

   This service name is an operator-created connection alias, not a supplied credential or evidence that access exists. If the prerequisite is absent, apply its reviewed file first with the same command and `-f supabase/migrations/20260929000000_register_x_handle.sql`, then immediately apply the additive migration. The owner may instead execute the exact files in the selected project's SQL editor. Never place connection secrets in the command, repository or evidence.

3. Confirm `x_handle_registry` is absent from the exposed API schemas. Confirm no client role can use the schema or directly read/write its tables or administrator views. Check definitions and effective privileges with the SQL below. Both new RPCs must be security-definer with an empty search path; only `anon` receives client execution. `PUBLIC` and `authenticated` must not inherit execution. Investigate any unexpected inherited grant.
4. Before any authorized acceptance test, require zero rows in all three acknowledged tables, zero total/active handles and zero eligible handles. The owner states there is no collected user data to migrate. If any new-registry rows already exist, stop and reconcile their provenance; do not erase them to manufacture an empty result.

```sql
SELECT clock_timestamp() AS checked_at;
SELECT * FROM x_handle_registry.username_counts;
SELECT count(*) AS eligible_count FROM x_handle_registry.feedback_dm_eligible_handles;
SELECT count(*) AS grants FROM x_handle_registry.sharing_grants;
SELECT count(*) AS acknowledged_handles FROM x_handle_registry.acknowledged_handles;
SELECT count(*) AS grant_handles FROM x_handle_registry.grant_handles;

SELECT n.nspname, c.relname, c.relrowsecurity, c.relacl
FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'x_handle_registry';
SELECT p.oid::regprocedure, p.prosecdef, p.proconfig, p.proacl
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('register_x_handle', 'report_x_activity_v1', 'withdraw_x_sharing_v1');
SELECT role_name,
  has_schema_privilege(role_name, 'x_handle_registry', 'USAGE') AS schema_access,
  has_function_privilege(role_name, 'public.register_x_handle(text)', 'EXECUTE') AS legacy,
  has_function_privilege(role_name, 'public.report_x_activity_v1(uuid,text,text,bigint,text)', 'EXECUTE') AS report,
  has_function_privilege(role_name, 'public.withdraw_x_sharing_v1(uuid,text,text)', 'EXECUTE') AS withdraw
FROM (VALUES ('anon'), ('authenticated')) r(role_name);
SELECT role_name, relation_name,
  has_table_privilege(role_name, relation_name, 'SELECT,INSERT,UPDATE,DELETE') AS any_access
FROM (VALUES ('anon'), ('authenticated')) r(role_name)
CROSS JOIN (VALUES ('x_handle_registry.sharing_grants'),
 ('x_handle_registry.acknowledged_handles'), ('x_handle_registry.grant_handles'),
 ('x_handle_registry.username_counts'), ('x_handle_registry.feedback_dm_eligible_handles')) t(relation_name);
```

Expected role results are `false,false,true,true` for `anon` and all false for `authenticated`. All relation access checks are false. All three new tables have RLS enabled. Administrator views remain private; RLS on views is not required.

## Gateway checks before client installation

Use only the selected project's publishable key in `apikey`, with no bearer login session. Set the two public configuration variables locally, turn off shell tracing, and assert the destination before running probes. Do not log request headers.

```sh
set -eu
set +x
test "$SLOP_FACTORY_SUPABASE_URL" = 'https://toiylcfpbryztcfjievv.supabase.co'
test -n "$SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY"
curl --silent --show-error --include \
  "$SLOP_FACTORY_SUPABASE_URL/rest/v1/rpc/report_x_activity_v1" \
  -H "apikey: $SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY" \
  -H 'Content-Type: application/json' \
  --data '{"p_grant_id":null,"p_capability":null,"p_disclosure_version":"x-username-feedback-v1","p_sequence":0,"p_handle":"home"}'
curl --silent --show-error --include \
  "$SLOP_FACTORY_SUPABASE_URL/rest/v1/rpc/withdraw_x_sharing_v1" \
  -H "apikey: $SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY" \
  -H 'Content-Type: application/json' \
  --data '{"p_grant_id":null,"p_capability":null,"p_disclosure_version":"x-username-feedback-v1"}'
curl --silent --show-error --include \
  "$SLOP_FACTORY_SUPABASE_URL/rest/v1/rpc/register_x_handle" \
  -H "apikey: $SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY" \
  -H 'Content-Type: application/json' --data '{"p_handle":"home"}'
```

The new RPCs must return a validation 4xx with SQLSTATE `22023` and no mutation. The old RPC must return permission denial or unavailable-function status, not validation `22023` and never 2xx. A 502 or connection failure proves neither. Requery the empty registry after the probes.

For each of `sharing_grants`, `acknowledged_handles`, `grant_handles`, `username_counts`, and `feedback_dm_eligible_handles`, request `/rest/v1/RELATION?limit=0` using the publishable key and `Accept-Profile: x_handle_registry`, then repeat without that header. Require denial or missing relation and no returned rows; a successful empty result is insufficient proof of denial. Direct write denial is covered by the read-only effective-privilege query and the disposable SQL suite. Do not issue live table mutation probes, including POST, PATCH or DELETE.

Backend readiness requires the migration, empty counts, private schema/privileges, both new RPC validation checks and old RPC rejection to pass. Install the verification client only after that gate. Successful report/withdraw transactions then use the owner's actual acknowledged app flow; do not invent synthetic users or retain an eligibility export.

## Controlled sign-in and app checks

Use a separate macOS test user for isolated preferences and WebKit cookies where possible. `--app-data-folder` alone does not isolate them. Quit other app instances. Use a local MP4, enable Draft only from the first launch, and avoid model-generation triggers. The manual draft branch skips normal background launch scheduling. It cannot alone prove ordinary startup or automatic-window behavior; record controlled native fixture coverage separately.

```sh
set -eu
set +x
unset SLOP_FACTORY_SUPABASE_URL SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY
verification_data="$(mktemp -d /tmp/slop-sharing-live.XXXXXX)"
verification_video='/absolute/path/to/owner-approved-local.mp4'
verification_destination="$(plutil -extract SlopFactorySupabaseURL raw '.build/app/Slop Factory Verification.app/Contents/Info.plist')"
test "$verification_destination" = 'https://toiylcfpbryztcfjievv.supabase.co'
'.build/app/Slop Factory Verification.app/Contents/MacOS/SlopFactory' \
  -draftOnly YES --app-data-folder "$verification_data" --draft-video "$verification_video"
```

The launch block unsets runtime overrides so it uses the verified bundled configuration. Verify the bundled publishable key locally against the owner-provided value without including it in evidence. Require the embedded URL to match the selected destination; retain `-draftOnly YES` on every launch. If necessary set the repository URL from the menu and relaunch the same command. Never click Post or Check now, send a DM, or trigger a release workflow. Inspect and discard the prepared draft. The owner handles sign-in and account switches.

Record each check independently, including missing accounts, unexercised provider popups or instrumentation limits:

| Action | Required observation |
| --- | --- |
| Unknown choice, including an existing X session | Disclosure appears, account-read instrumentation remains at zero, no ordinary reports or persisted username |
| Dismiss, then menu login/manual draft | Sharing stays off; login and draft preparation work; no repeat interruption in the same process |
| Continue without sharing, relaunch | Decline persists without usernames; account reads and ordinary reports remain zero |
| Upgrade with old pending/delivered fixture state | Old queue is unused/cleaned; no old upload or implied acknowledgement; use local isolated fixture coverage, never alter live user state |
| Accept in an already-open window | Exact disclosure/version/time save first; observer starts; one report for its own confirmed handle |
| Poll, navigate, rediscover same account, provider popup | No additional event; provider popup never contributes a second top-level activity |
| Reopen window, switch to second authorized account, use two windows | New qualifying activity is attributed to that window's handle; first registration stays unchanged |
| Change choice while a window is open | Observer/timers and account reads stop; queued callbacks cannot report |
| Offline decline, relaunch, recovery | Pending withdrawal wording persists; only withdrawal retries; server confirmation clears pending status |
| Re-acknowledge while withdrawal is pending | Fresh grant; old grant withdrawal completes before replacement reporting |

Use account-read counters from the controlled WebKit fixture to establish the absence of analytics DOM queries, handlers and timers before acknowledgement and after teardown. A network trace alone cannot prove that boundary. If the shipped-style artifact cannot expose equivalent counters safely, mark its live no-read claim unproven and cite the controlled fixture separately. Do not claim local instrumentation was collected from live X.

Observe the user's authorized handles through administrator queries without reading capability digests into the report:

```sql
SELECT clock_timestamp() AS checked_at;
SELECT handle, first_registered_at FROM x_handle_registry.acknowledged_handles
WHERE handle IN ('OWNER_HANDLE_1', 'OWNER_HANDLE_2');
SELECT gh.handle, gh.last_activity_at, g.disclosure_version,
       g.acknowledged_at, g.withdrawn_at, g.highest_sequence
FROM x_handle_registry.grant_handles gh
JOIN x_handle_registry.sharing_grants g USING (grant_id)
WHERE gh.handle IN ('OWNER_HANDLE_1', 'OWNER_HANDLE_2');
SELECT * FROM x_handle_registry.username_counts;
SELECT count(*) AS authorized_accounts_eligible
FROM x_handle_registry.feedback_dm_eligible_handles
WHERE handle IN ('OWNER_HANDLE_1', 'OWNER_HANDLE_2');
```

Substitute only the owner's authorized normalized handles. A fresh registration timestamp must fall between database checks around the first accepted report. Repeated use must retain that timestamp and one global row per handle. Withdrawal preserves total registration history but removes this grant's activity and feedback eligibility. Another installation's current grant can keep that handle eligible.

For this verification, the owner selected simulated network failures instead of a real outage. Reproduce the accepted checks with `swift test --disable-sandbox --filter XSharingSimulatedOutageTests`. The test-only URLProtocol intercepts every request, returns a network-disconnected error and later successful responses, and retains the selected logical destination. It uses no real credentials, contacts no live backend and changes no Mac network setting. Record its outcome as simulated recovery, separately from live registration/withdrawal evidence. The prior sudo helpers are cancelled and exit before changing network settings.

For a separately authorized future real outage check, block only this app's selected Supabase host using a reviewed test-machine rule; keep X available. Record activation/removal times and always remove the rule. Wait beyond the ordinary 30-second event deadline, restore access and require no stale replay. Only reopening a qualifying window may create fresh activity. Repeat with decline while blocked: collection stops immediately, the UI says "Sharing is off on this Mac. Removing feedback contact permission when a connection is available.", and recovery sends withdrawal without a username. Confirmation changes this to "Sharing is off on this Mac." Never attach the withdrawal capability.

Lost-response retries must retain the same sequence and server timestamp. Withdrawal-before-report, concurrent report/withdraw, exact 30-day boundaries, capability mismatch, multi-install independence and disclosure-version changes belong to the reproducible disposable contract suite. Record those as local evidence unless an explicitly authorized live procedure actually exercised them. Do not mutate production timestamps or add synthetic grants to imitate those checks.

Inspect sanitized request structure: reports contain only grant UUID, app-issued capability, disclosure version, sequence and normalized handle; withdrawal omits the handle. Transport uses ephemeral cookie-free networking with redirect rejection. No X password, cookie, token, post text, model identifier or client timestamp belongs in either payload. No post or DM is sent by verification.

## Meaning of the results

The labels are **Total registered X usernames** and **Active X usernames in the last 30 days**. They count client-reported handles, not verified people; a renamed account can count twice. Activity means the first confirmed account in an acknowledged top-level login or posting window, or a distinct account change there. Draft only and ordinary posting windows qualify; successful publication is unnecessary. App launch alone, passive model checks, popups, DOM polling and retries do not qualify.

Active membership requires a non-withdrawn current-version grant with server receipt time strictly newer than database time minus 30 days and no later than database time. Exactly 30 days old is excluded. Offline reports expire and may undercount registration and activity. The choice is installation- and destination-scoped. One acknowledgement covers counts and possible feedback DMs; no DMs are implemented or sent. An offline decline stops local reads immediately, but remote eligibility changes when withdrawal arrives.

## Rollback without restoring legacy uploads

An authorized administrator runs the following on the same selected project if reporting must stop. Record UTC time and result. Keep withdrawal callable, preserve all data and tombstones, and keep the private schema unexposed.

```sql
BEGIN;
REVOKE EXECUTE ON FUNCTION public.report_x_activity_v1(uuid,text,text,bigint,text)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.register_x_handle(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_x_sharing_v1(uuid,text,text) TO anon;
COMMIT;
```

Repeat the effective privilege checks: report and legacy execution must be false for both client roles; withdrawal remains true only for `anon`. Repeat the invalid withdrawal gateway probe to prove the route remains available. A report rejection cannot by itself establish withdrawal availability.

Suspend all feedback outreach operationally. This release has no DM sender to disable. The existing eligibility view alone is not a rollback kill switch; no future operator or service may use it for outreach while rollback is active. Do not export candidates. If an independently deployed sender exists, its owner must confirm it is paused before rollback is treated as complete.

Database permission changes stop accepted uploads from installed binaries. They do not stop an older binary's local observation, remove an already queued username, or remotely change its UI. Explain that distinction in incident records. New clients can turn sharing off from the menu or the X window title-bar button and still send withdrawal. Do not delete local state needed for withdrawal, drop tables, delete remote rows, or re-enable `register_x_handle` as fallback.

Removing backend configuration from a future build is not a substitute for leaving withdrawal available. Existing withdrawals retain their original destination configuration, but a rollback plan must verify this behavior and preserve their local state. Clearing repository URL/key variables restores bundled defaults; it is not a disable switch. No build setting changes an already installed binary.

Resume new reporting only after the repair, repeated affected checks and separate operational authorization. Do not restore the legacy RPC. Client release publication requires separate authorization after live checks pass; it is outside CODING-2385.
