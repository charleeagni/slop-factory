# CODING-2385 local backend and browser-fixture evidence

Executed 2026-09-29 at approximately 13:29 UTC against shared working tree based on `66b6a4de351cb9039d427b395a0415d757247243`. The tree contains uncommitted implementation changes, so HEAD alone does not identify the tested artifact. Verification added an empty-registry assertion to the SQL suite and one public coordinator transport/privacy test. No production files were changed.

Environment: macOS 26.2 build 25C56; Node v24.21.0; PostgreSQL 17.10 Homebrew.

## Results

| Command | Result | Evidence |
| --- | --- | --- |
| `node Scripts/test-x-account-observer.mjs` | Passed, exit 0 | `/tmp/2385-observer.log` |
| `node Scripts/test-x-compose-dialog.mjs` | Passed, exit 0 | `/tmp/2385-compose.log` |
| `bash Scripts/test-x-handle-database.sh` | Passed, exit 0 outside sandbox | `/tmp/2385-postgres.log` |

The initial database attempt failed during `initdb` because the sandbox denied `shmget`. The approved rerun used the unchanged script outside the sandbox. It created a disposable `/tmp` PostgreSQL cluster, listened only on its unique Unix socket, applied both repository migrations, ran the SQL contracts, exercised deterministic overlapping transactions in both report-first and withdrawal-first order, and deleted the cluster on exit. No configured destination or remote service was contacted.

## Coverage

Observer fixtures execute JavaScript extracted from the production Swift source. They count account DOM queries and assert zero before enabling; validate trusted HTTPS origins, main-frame behavior, profile-link-only extraction, normalization, account switching/logout, unchanged-account suppression, isolated window state, choice generation metadata, explicit teardown, cancellation of pending callbacks, and restart of an existing document under a new generation. The fixtures are a JavaScript VM, not WebKit or the shipped native app.

Compose fixtures execute scripts extracted from the production posting source. They confirm compose-dialog upload readiness and button scope, including disabled and absent dialogs. A fake button receives a click inside the VM; no real X post is created. They do not prove native posting availability under decline.

Actual PostgreSQL contracts verify one global row for a handle across grants; immutable first registration; duplicate and altered-duplicate no-ops; unchanged acknowledgement/activity timestamps after lost-response retry; positive signed-64-bit sequences and reservation gaps; strict lower thirty-day boundary and inclusive current-time upper boundary; current-version and acknowledgement filtering; independent grant eligibility; withdrawal before/after reporting and repeated withdrawal; deterministic concurrent withdrawal/report in both lock orders; malformed input rejection without writes; capability mismatch rejection; legacy RPC execution denial; both client roles denied direct table/view operations; RLS and SECURITY DEFINER empty-search-path configuration. Administrator fixtures simulate a successor reporting version inside a rollback and confirm the existing withdrawal RPC still accepts v1, including a never-reported tombstone.

Static migration inspection matches the minimum remote records, capability SHA-256 storage, additive registry, no legacy backfill/deletion, current-version counts/eligibility, and explicit anon-only RPC grants. No integration defect was found in these checks.

## Limits

These runs do not verify Supabase gateway/schema exposure, live permissions or migration state, the owner-selected destination, actual authorized X sign-in, native disclosure presentation, provider popup behavior, or live client/server exchange. The SQL rerun explicitly asserts zero total, zero active, and no feedback candidates before the first synthetic report. Native integration and gateway evidence remain separate. No post, DM, live migration, release publication, or remote data deletion occurred.

## Tested file SHA-256

```text
4d9482e3c756891dd20fddf9e63f331daefbb9eb401f2219797137914599b94c  supabase/migrations/20260929010000_acknowledged_x_activity.sql
0a0461554348d9396acdaa72a4b2883f05fca35514ea1671273f68a0d21b6fb7  supabase/tests/x_handle_registrations.sql
bcf7361634ff339b9fbd330ccec8bdecd4e6c4f0cfa96b404f94952cef4dce81  Scripts/test-x-handle-database.sh
0efd29cfd0ac405a79041cc03eb8ae2dea3e21e01828731917066fc347bff085  Scripts/test-x-account-observer.mjs
bbadfe8a90b4664e86c58a1910a4a0642933bac60830d8599e457ad77b66056c  Scripts/test-x-compose-dialog.mjs
dc8096d4ed6d7b4d02ece8d413fa11702e112d0bda73521e276f05a205ace40a  Sources/FactoryCore/XAccountObservationScript.swift
```

## Additional public transport/privacy validation

`swift test --filter XSharingPayloadTests` passed one Swift Testing test on 2026-09-29 at 13:32:40 UTC. Log: `/tmp/2385-payload.log`. Initial compilation was denied compiler-cache access by the sandbox; approved rerun exposed a nested `#require` macro error in the new test helper. Splitting the nested macro fixed that test-only compile error. The completed test passed against unchanged production code; this is coverage validation, not a claimed behavioral red/green fix.

The test drives acknowledgement, window observation, and decline through the existing coordinator public methods with a controlled transport and temporary storage. It checks exact report and withdrawal JSON key allowlists, POST endpoints, exact apikey and content-type headers, absence of Authorization and Cookie, `httpShouldHandleCookies == false`, UUID grant format and a 64-character lowercase hexadecimal capability, owner-only 0600 state permissions, and absence of the observed username from both acknowledged state and pending withdrawal state. The transport returns HTTP 400 on withdrawal to retain the outbox for that privacy assertion. It makes no network requests. Format checks do not statistically prove entropy; source inspection confirms the capability uses `SecRandomCopyBytes` on 32 bytes.

Additional test SHA-256: `40646992943aabe66c944da58ae3d814490cf63a477ff6a2e817d2932ae208b1` for `Tests/FactoryCoreTests/XSharingPayloadTests.swift`.
