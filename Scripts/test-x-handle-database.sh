#!/usr/bin/env bash
# Creates an isolated local PostgreSQL cluster, never connects to a configured project.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
for tool in initdb pg_ctl psql; do
    command -v "$tool" >/dev/null || { echo "Required tool missing: $tool (install PostgreSQL)" >&2; exit 1; }
done
cluster_root="$(mktemp -d /tmp/slop-x-registry.XXXXXX)"
cleanup() {
    pg_ctl -D "$cluster_root/data" -m immediate stop >/dev/null 2>&1 || true
    rm -rf "$cluster_root"
}
trap cleanup EXIT
initdb -D "$cluster_root/data" -U registry_test --auth=trust --no-locale --encoding=UTF8 >/dev/null
# Unix socket only, isolated by its unique directory; no network listener.
pg_ctl -D "$cluster_root/data" -l "$cluster_root/postgres.log" \
    -o "-k $cluster_root -h ''" -w start >/dev/null
psql_args=(-X -v ON_ERROR_STOP=1 -h "$cluster_root" -U registry_test -d postgres)
psql "${psql_args[@]}" -q <<'SQL'
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
GRANT USAGE ON SCHEMA public TO anon, authenticated;
-- Match Supabase's permissive defaults so the migration must revoke them.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;
SQL
for migration in "$repo_root"/supabase/migrations/*.sql; do
    [[ -f "$migration" ]] && psql "${psql_args[@]}" -q -f "$migration"
done
psql "${psql_args[@]}" -q -f "$repo_root/supabase/tests/x_handle_registrations.sql"
# Hold the first transaction open until the second connection is observably
# blocked by it. This exercises both lock orders, rather than hoping scheduling
# makes two simultaneously launched processes cover them.
for first in report withdraw; do
    if [[ "$first" == report ]]; then
        grant_id=00000000-0000-0000-0000-000000000010
        first_call="public.report_x_activity_v1('$grant_id', repeat('e',64), 'x-username-feedback-v1', 1, 'race_report')"
        second_call="public.withdraw_x_sharing_v1('$grant_id', repeat('e',64), 'x-username-feedback-v1')"
    else
        grant_id=00000000-0000-0000-0000-000000000011
        first_call="public.withdraw_x_sharing_v1('$grant_id', repeat('e',64), 'x-username-feedback-v1')"
        second_call="public.report_x_activity_v1('$grant_id', repeat('e',64), 'x-username-feedback-v1', 1, 'race_withdraw')"
    fi
    mkfifo "$cluster_root/$first.sql"
    PGAPPNAME=registry_first psql "${psql_args[@]}" -q <"$cluster_root/$first.sql" >"$cluster_root/$first-first.out" &
    first_pid=$!
    exec 3>"$cluster_root/$first.sql"
    printf 'BEGIN; SET LOCAL ROLE anon; SELECT %s;\n\\! touch %s/ready-%s\n' "$first_call" "$cluster_root" "$first" >&3
    for attempt in {1..200}; do
        [[ -f "$cluster_root/ready-$first" ]] && break
        sleep 0.02
    done
    [[ -f "$cluster_root/ready-$first" ]] || { echo "First transaction did not acquire grant" >&2; exit 1; }
    PGAPPNAME=registry_second psql "${psql_args[@]}" -q -c "SET ROLE anon; SELECT $second_call;" >"$cluster_root/$first-second.out" &
    second_pid=$!
    blocked=false
    for attempt in {1..200}; do
        if [[ "$(psql "${psql_args[@]}" -Atqc "SELECT EXISTS (SELECT FROM pg_stat_activity a JOIN pg_stat_activity b ON b.pid = ANY(pg_blocking_pids(a.pid)) WHERE a.application_name = 'registry_second' AND b.application_name = 'registry_first')")" == t ]]; then
            blocked=true
            break
        fi
        sleep 0.02
    done
    [[ "$blocked" == true ]] || { echo "Second transaction did not block on first ($first)" >&2; exit 1; }
    printf 'COMMIT;\n' >&3
    exec 3>&-
    wait "$first_pid"
    wait "$second_pid"
done
psql "${psql_args[@]}" -q <<'SQL'
SET ROLE anon;
DO $$ BEGIN
 IF public.report_x_activity_v1('00000000-0000-0000-0000-000000000010', repeat('e',64), 'x-username-feedback-v1', 2, 'race_report')->>'status' <> 'withdrawn'
 OR public.report_x_activity_v1('00000000-0000-0000-0000-000000000011', repeat('e',64), 'x-username-feedback-v1', 2, 'race_withdraw')->>'status' <> 'withdrawn' THEN
 RAISE EXCEPTION 'Concurrent withdrawal failed to permanently revoke grant'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF EXISTS (SELECT FROM x_handle_registry.feedback_dm_eligible_handles WHERE handle IN ('race_report','race_withdraw'))
 OR NOT EXISTS (SELECT FROM x_handle_registry.acknowledged_handles WHERE handle = 'race_report')
 OR EXISTS (SELECT FROM x_handle_registry.acknowledged_handles WHERE handle = 'race_withdraw')
 OR (SELECT acknowledged_at IS NOT NULL FROM x_handle_registry.sharing_grants WHERE grant_id='00000000-0000-0000-0000-000000000011') THEN
 RAISE EXCEPTION 'Concurrent withdrawal left grant eligible'; END IF;
END $$;
SQL
echo "X handle database checks passed (disposable PostgreSQL)."
