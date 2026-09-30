# Slop Factory

<p align="center">
  <img alt="An OpenAI-generated rainy noodle-stall scene recorded by Slop Factory" src="docs/recording-evidence/openai.png" width="720">
  <br>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple">
</p>

> "Slop Factory recognizes when there is a new model and it automatically burns all of your tokens and creates new slop. It also posts it automatically on Twitter without you even being in the loop."
>
> From the Slop Factory release ad.

Slop Factory is a macOS menu bar app that watches the models available through your local `claude` and `codex` CLIs. When it finds a new model, it gives that model the same frozen prompt, records the result, and posts the video to X. The first check records your existing models without posting them.

## Install

Prebuilt downloads are currently unavailable. Build from source with macOS 14 or later and Swift 6:

1. Clone this repository and run `Scripts/build-app.sh` from its directory.
2. Copy `.build/app/Slop Factory.app` into Applications.
3. Open it. Local builds are ad hoc signed; macOS may require you to allow the app through System Settings.
4. Follow the first-launch prompts. The app finds any installed `claude` and `codex` CLIs and opens X for you to sign in. Sign-in popups open in their own app windows.

Every post includes this repository's URL automatically, including builds from source. No repository setup is needed.

You need at least one of the `claude` or `codex` CLIs installed and signed in. You do not need Python, Chrome, ffmpeg, or an X developer account. Use **Draft only** in the menu if you want to inspect a post before clicking Post yourself.

For each Codex build, Slop Factory checks the Codex executables on your saved shell PATH and in the standard ChatGPT app locations, then uses the newest installed CLI version it can identify. Every model run uses medium reasoning effort, regardless of your personal CLI defaults. Slop Factory does not pin a CLI version.

## What the ad leaves out

Slop Factory uses your own CLI subscriptions and can consume tokens. It runs Claude with permission checks skipped and Codex with approvals disabled inside a new folder for each model. It saves the CLI output and generated files under `~/Library/Application Support/Slop Factory/`.

By default, the app records the generated page and uploads the video to your X account without asking each time a new model appears. Keep the app closed, or use **Draft only**, if you do not want automatic posts. Model availability comes from local CLI data and may lag a provider announcement. The app and its posts are a joke about AI demos, not a claim that a model achieved AGI.

If a model build fails or produces no page or image, Slop Factory keeps the run log and skips X. New models that fail remain eligible for a later check.

## X username sharing

Before observing your X username, Slop Factory asks you to choose **Acknowledge and share my X username** or **Continue without sharing**. Closing the dialog leaves sharing off. Login, posting, Draft only, and model checks remain available with sharing off. Review or change the choice through **X username sharing…** in the menu.

The disclosure is: "Slop Factory stores your X username to count distinct users and users active in the last 30 days. We may send you a direct message on X to ask about your experience with Slop Factory. We do not collect your X password, cookies, or login tokens for this purpose."

This choice applies to X accounts used in this installation and its configured destination. Another installation has its own choice. No DMs are sent by this feature.

## Build from source

Requires macOS 14 or later and Swift 6. Run `swift test` for the core tests, then `Scripts/build-app.sh` to make `.build/app/Slop Factory.app`. Local builds are ad hoc signed; set `CODESIGN_IDENTITY` to a Developer ID Application certificate name to sign with the hardened runtime.

The release workflow signs and notarizes when these repository secrets are set: `DEVELOPER_ID_CERTIFICATE_P12` (base64 `.p12`), `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_APP_PASSWORD` (an app-specific password). The workflow refuses to publish without a Developer ID certificate. A locally signed and notarized build can also be uploaded to the release.

### Configure X username sharing

FactoryCore intentionally removes the public `XHandleRegistrationCoordinator`, `XHandleRegistrationClock`, and `SystemXHandleRegistrationClock` APIs. Use `XUsernameSharingCoordinator` in `XUsernameSharing.swift` for the acknowledged lifecycle. Shared handle/origin validation lives in `XHandleValidation.swift`, destination/key validation in `XHandleRegistrationConfiguration.swift`, and the cookie-free transport remains available. CODING-2340 is a superseded historical contract; the finished CODING-2359 specification governs acknowledgement, expiring activity, and withdrawal. Historical upgrade tests use inert old-state fixtures, not an operational legacy uploader.

The [September 30 verification report](docs/x-sharing-verification-2026-09-30.md) is the current evidence for the integrated build. The owner-selected backend is already migrated and verified, including production permissions and gateway checks. Live acknowledged registration, duplicate-free relaunch, online withdrawal, declined-state relaunch, and Draft-only preparation passed. The implementation is ready for Review within the owner-approved scope; Review does not authorize release publication.

The owner skipped live second-account switching and a real network outage. Approved simulated outage, expiry, withdrawal, and recovery checks passed. A provider login popup was not exercised in live X; controlled account-attribution and native popup coverage passed. Live X no-read instrumentation is not claimed; controlled fixtures establish that boundary. See the [rollout and rollback runbook](docs/x-sharing-rollout-runbook.md) for the evidence gates and procedures. The [September 29 recovery report](docs/x-sharing-recovery-verification-2026-09-29.md) covers local recovery and race checks. The [historical legacy report](docs/x-handle-verification-report-2026-09-29.md) describes superseded registration; an upload delivery acknowledgement was not user consent.

The owner's selected project, `https://toiylcfpbryztcfjievv.supabase.co`, and its public `sb_publishable_…` client key are bundled in `Resources/Info.plist`. Users do not configure Supabase. To build against another explicitly selected project, override both settings below. Never supply a secret or service-role key.

```sh
SLOP_FACTORY_SUPABASE_URL='https://YOUR_PROJECT.supabase.co' \
SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY='sb_publishable_YOUR_KEY' \
Scripts/build-app.sh
```

The build stores these public settings as `SlopFactorySupabaseURL` and `SlopFactorySupabasePublishableKey` in the app's Info.plist. The same environment variables override bundled settings for development when you launch the executable directly. The cookie-free client calls `report_x_activity_v1` and `withdraw_x_sharing_v1` with an `apikey` header, rejects redirects, and never copies browser credentials.

For a new explicitly selected destination, follow the migration instructions in [supabase/README.md](supabase/README.md) before distributing the client. Verify the prerequisite migration, apply it only if absent, then apply and verify the additive migration that revokes legacy `register_x_handle` execution. Building does not deploy migrations. The already deployed selected project `toiylcfpbryztcfjievv` has passed these checks; do not rerun its one-time migrations.

Release builds use the bundled defaults. Non-empty repository Actions variables with those same names override them. To disable sharing in a future build, set `SLOP_FACTORY_DISABLE_HANDLE_REGISTRATION=1`; the build removes both settings. Clearing the URL/key Actions variables restores bundled defaults. Empty runtime URL/key variables disable collection after restarting the executable. Missing or invalid configuration disables observation and reports.

The new `x-username-sharing-v1.json` state stores the choice, disclosure version, time, grant, reserved sequence, and username-free withdrawal outbox with owner-only access. The old analytics queue is removed without replaying handles. A cleanup or state-read failure disables sharing and displays a diagnostic; X cookies, model state, and app runs are preserved. `--app-data-folder <directory>` relocates app data for development.

An acknowledged top-level login or posting window reports its first confirmed account, then distinct account changes. Reopening a window qualifies again. Popups, polling, navigation, and rediscovery of the same account do not add events. Ordinary activity stays in memory for at most 30 seconds and is never replayed after restart. One report is sent at a time per grant. Network errors, HTTP 408/429, and server errors allow one retry after five seconds. A longer Retry-After is honored only if it fits inside the original 30-second deadline. Each request times out after at most 15 seconds, shortened to the remaining deadline. Closing a window, changing its account, or declining drops its pending reports. Outages can lose reports and undercount both registration and activity; only later qualifying window use creates another event.

Declining stops local capture immediately and saves withdrawal work without usernames. Until the server confirms withdrawal, the menu says **Sharing is off on this Mac. Removing feedback contact permission when a connection is available.** Confirmation changes this to **Sharing is off on this Mac.** The username-free withdrawal outbox survives restart. Withdrawal is attempted immediately, then after one minute, five minutes, and every 30 minutes; a longer valid Retry-After takes precedence. Permanent client errors remain pending and receive one further attempt on a later launch or relevant configuration repair. While declined, only permission removal retries continue. Another installation's independently acknowledged grant remains eligible. Re-acknowledgement creates a fresh grant, waits for pending withdrawals at the same destination before reporting, and never revives a withdrawn grant. A disclosure-version or destination change requires a new choice and withdraws the old grant at its original destination; rotating a publishable key for the same destination preserves the choice.

If saving a decline fails, capture stops in the running app and the menu says the choice was not saved. That change may not survive restart. Unreadable state is preserved for repair rather than overwritten, because it may contain the capability needed for withdrawal.

Administrator queries in [supabase/README.md](supabase/README.md) provide **Total registered X usernames** and **Active X usernames in the last 30 days**. Total preserves historical acknowledged registration after withdrawal. Active includes distinct handles with a current, non-withdrawn grant and activity strictly inside the trailing 30 days. These are client-reported handles, not verified people; renamed handles can count separately. Activity measures the window usage described above. Client roles cannot read the private registry or DM eligibility list. No legacy rows are backfilled.

Run the focused checks with:

```sh
swift test
node Scripts/test-x-account-observer.mjs
node Scripts/test-x-compose-dialog.mjs
Scripts/test-x-sharing-browser.sh
Scripts/test-recorder.sh
Scripts/test-x-handle-database.sh
```

The recorder check needs an awake, signed-in desktop session and takes several minutes.

The database check needs PostgreSQL's `initdb`, `pg_ctl`, and `psql` on PATH. It creates and removes its own local cluster, with no network listener, and never uses your configured project. Core tests cover registration recovery with fake transport and time and temporary local state. These checks do not establish live X ownership or verify a production deployment.

## License

MIT. See [LICENSE](LICENSE).
