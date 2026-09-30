# Acknowledged X username registry

The app must save an explicit choice for `x-username-feedback-v1` before observing or reporting a username. Login, posting, Draft only, and model checks remain available without sharing. One acknowledgement covers counts and possible feedback DMs. This feature sends no DMs.

The owner-selected Supabase project `toiylcfpbryztcfjievv` is already migrated and verified. Do not rerun its one-time migrations. For a new owner-selected destination, inspect migration history and object definitions, then apply only missing migrations in filename order before deploying the client. If the prerequisite legacy migration is absent, apply it and immediately apply the additive acknowledgement migration in the same maintenance window, before client deployment. Neither migration is an idempotent reapply script; investigate any conflicting or partially applied schema. This repository does not deploy them. The second migration creates a fresh acknowledged registry and revokes the legacy `register_x_handle` RPC in the same transaction. It neither copies nor deletes historical registry rows. Old verification rows are not acknowledged users.

The client intentionally removes the public legacy `XHandleRegistrationCoordinator` and its `XHandleRegistrationClock`/`SystemXHandleRegistrationClock` APIs. `XUsernameSharingCoordinator` uses the retained cookie-free transport for the two acknowledged RPCs below. CODING-2340 remains historical; the finished CODING-2359 specification supersedes its automatic uploads and durable username replay. Removing the legacy client does not change migration order or permit restoring `register_x_handle` execution.

Keep `x_handle_registry` out of exposed API schemas. All registry tables have RLS enabled and deny direct access to `PUBLIC`, `anon`, and `authenticated`. Only the two narrow public RPCs grant execution to `anon`. They use security-definer functions with an empty search path. Never grant client access to the administrator views or put privileged keys in the app.

## RPC contract

`report_x_activity_v1(p_grant_id uuid, p_capability text, p_disclosure_version text, p_sequence bigint, p_handle text)` returns a JSON object with `status` equal to `recorded`, `duplicate`, or `withdrawn`.

`withdraw_x_sharing_v1(p_grant_id uuid, p_capability text, p_disclosure_version text)` returns `{"status":"withdrawn"}`, including repeated withdrawals and withdrawal before the first report.

The capability is 32 cryptographically random bytes encoded as exactly 64 lowercase hexadecimal characters. The server stores only SHA-256 of the decoded bytes. The supported disclosure version is `x-username-feedback-v1`. Report sequences are positive signed 64-bit integers. Handles must already be lowercase, contain 1–15 ASCII letters, digits, or underscores, and must not be reserved X routes. Invalid values and credential mismatches raise SQLSTATE `22023`; invalid UUIDs or overflowing integers are rejected by PostgreSQL's argument conversion. Error messages never contain capabilities.

Each RPC creates the grant if absent and locks it before acting. A report at or below the high-water sequence does nothing, even if its handle differs. Fresh reports preserve the first acknowledged registration time, update activity using one server receipt timestamp, and advance the sequence atomically. Withdrawal permanently closes only its grant. A tombstone blocks a delayed report even when no handle was registered. Reporting accepts only the current disclosure. Future disclosure updates must retain every previously supported version in withdrawal validation, including tombstones for grants never reported. The local SQL suite simulates a successor reporting version within a rolled-back transaction to verify that v1 withdrawal remains available; it does not introduce another production disclosure.

These capabilities manage unverified reporting grants. They do not verify ownership of an X account or authorize any other application access.

## Administrator queries

Run these only with administrator database access:

```sql
SELECT total_registered_x_usernames AS "Total registered X usernames",
       active_x_usernames_in_last_30_days AS "Active X usernames in the last 30 days"
FROM x_handle_registry.username_counts;

SELECT handle FROM x_handle_registry.feedback_dm_eligible_handles ORDER BY handle;
```

Total counts distinct handles ever acknowledged. Withdrawal preserves that history. Active counts distinct handles with a non-withdrawn current-version grant and activity strictly newer than database time minus 30 days and no later than database time. Exactly 30 days old does not qualify. DM eligibility requires at least one non-withdrawn acknowledged current-version grant, irrespective of activity age.

Counts represent client-reported handles, not verified people. Renamed handles can count separately. Activity means first confirmed account use in an embedded top-level X login or posting window, or a distinct account change in that window. Launch alone, DOM polling, navigation, provider popups, and request retries do not add activity.

Another independently acknowledged installation may keep the same handle active and eligible after this Mac withdraws. An offline decline stops local sharing immediately, but removes remote eligibility only when withdrawal reaches the server. Any future outreach must check current eligibility at send time.

## Verification and rollout

The [September 30 verification report](../docs/x-sharing-verification-2026-09-30.md) is the current evidence for the already migrated owner-selected backend at `toiylcfpbryztcfjievv.supabase.co`. Production migration, permissions and gateway checks passed, as did live acknowledged registration, duplicate-free relaunch, online withdrawal, declined-state relaunch and Draft-only preparation. The [current rollout and rollback runbook](../docs/x-sharing-rollout-runbook.md) records the procedures and evidence gates. The integrated verification is ready for Review within the owner-approved scope; Review does not authorize release publication.

The owner skipped live second-account switching and the real network outage. Owner-approved simulated outage, event expiry, withdrawal and recovery checks passed, but do not prove live outage recovery. A live provider login popup was not exercised; controlled account-attribution and native popup coverage passed. Live X account-read instrumentation is not claimed. Bundled public configuration is not deployment access or authorization for further backend changes.

Run `Scripts/test-x-handle-database.sh` with PostgreSQL's `initdb`, `pg_ctl`, and `psql` on `PATH`. It creates and destroys a disposable local cluster on a temporary Unix socket, with no network listener or connection to a configured destination. It tests the actual migrations and both RPCs, including lost responses, altered duplicates, sequence gaps, immutable timestamps, two installations sharing one handle, tombstones, exact count boundaries, current-version filtering, invalid inputs, capabilities, private table access, and legacy exclusion. Concurrent report/withdrawal checks hold the first transaction open and observe the second blocked on its lock before releasing it, covering both request orders. Withdrawal after a reporting-version upgrade is checked in an isolated transaction.

For a new owner-selected destination, use its administrative tooling to verify the same RPC and privilege contracts before client deployment. Before its first acceptance test, confirm that the acknowledged registry has zero counts and no DM candidates. The deployed selected project passed these empty-registry checks before app testing; its later acknowledged rows are expected and must not be deleted to recreate that baseline. The old [live verification runbook](../docs/x-handle-live-verification.md) and [historical report](../docs/x-handle-verification-report-2026-09-29.md) describe the superseded registration feature; their successful legacy upload checks must not be used as acceptance of this flow. Do not execute live migrations or send test posts or DMs as part of local verification.

Ordinary activity remains memory-only and expires after 30 seconds. Outages can lose registration and activity events; old usernames must never replay at launch. Only the username-free withdrawal outbox persists retry work. Run the coordinator, observer, compose, and native integration checks alongside this SQL suite to verify offline recovery and cancellation across the complete client flow.

Rollback must disable execution of `report_x_activity_v1` and exclude feedback outreach while leaving `withdraw_x_sharing_v1` available. Never restore legacy upload execution as a fallback.
