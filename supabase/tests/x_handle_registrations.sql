-- Exercise the publishable-key RPC and administrator query seams.
DO $$ BEGIN
 IF (SELECT total_registered_x_usernames FROM x_handle_registry.username_counts) <> 0
 OR (SELECT active_x_usernames_in_last_30_days FROM x_handle_registry.username_counts) <> 0
 OR EXISTS (SELECT FROM x_handle_registry.feedback_dm_eligible_handles) THEN
 RAISE EXCEPTION 'Fresh acknowledged registry must have zero counts and no feedback candidates'; END IF;
END $$;
SET ROLE anon;
DO $$ BEGIN
 IF public.report_x_activity_v1('00000000-0000-0000-0000-000000000001', repeat('a',64), 'x-username-feedback-v1', 1, 'owner_42')->>'status' <> 'recorded' THEN
 RAISE EXCEPTION 'Expected recorded'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT total_registered_x_usernames FROM x_handle_registry.username_counts) <> 1 THEN
 RAISE EXCEPTION 'Expected one registered handle'; END IF;
END $$;

-- The administrator sees immutable registration and activity on duplicate delivery.
CREATE TEMP TABLE original_times AS
SELECT first_registered_at, last_activity_at FROM x_handle_registry.acknowledged_handles
JOIN x_handle_registry.grant_handles USING (handle) WHERE handle = 'owner_42';
SET ROLE anon;
DO $$ BEGIN
 IF public.report_x_activity_v1('00000000-0000-0000-0000-000000000001', repeat('a',64), 'x-username-feedback-v1', 1, 'other')->>'status' <> 'duplicate' THEN
 RAISE EXCEPTION 'Altered duplicate should be a no-op'; END IF;
END $$;
SELECT public.report_x_activity_v1('00000000-0000-0000-0000-000000000002', repeat('b',64), 'x-username-feedback-v1', 1, 'owner_42');
SELECT public.withdraw_x_sharing_v1('00000000-0000-0000-0000-000000000001', repeat('a',64), 'x-username-feedback-v1');
RESET ROLE;
DO $$ BEGIN
 IF (SELECT total_registered_x_usernames FROM x_handle_registry.username_counts) <> 1
 OR (SELECT active_x_usernames_in_last_30_days FROM x_handle_registry.username_counts) <> 1
 OR (SELECT count(*) FROM x_handle_registry.feedback_dm_eligible_handles) <> 1
 OR (SELECT first_registered_at FROM x_handle_registry.acknowledged_handles WHERE handle='owner_42') <> (SELECT first_registered_at FROM original_times)
 OR (SELECT last_activity_at FROM x_handle_registry.grant_handles WHERE grant_id='00000000-0000-0000-0000-000000000001') <> (SELECT last_activity_at FROM original_times)
 THEN RAISE EXCEPTION 'Duplicate changed history or withdrawal affected another grant'; END IF;
END $$;
SET ROLE anon;
SELECT public.withdraw_x_sharing_v1('00000000-0000-0000-0000-000000000002', repeat('b',64), 'x-username-feedback-v1');
SELECT public.withdraw_x_sharing_v1('00000000-0000-0000-0000-000000000002', repeat('b',64), 'x-username-feedback-v1');
SELECT public.withdraw_x_sharing_v1('00000000-0000-0000-0000-000000000003', repeat('c',64), 'x-username-feedback-v1');
DO $$ BEGIN
 IF public.report_x_activity_v1('00000000-0000-0000-0000-000000000003', repeat('c',64), 'x-username-feedback-v1', 1, 'delayed')->>'status' <> 'withdrawn'
 OR public.report_x_activity_v1('00000000-0000-0000-0000-000000000001', repeat('a',64), 'x-username-feedback-v1', 2, 'revived')->>'status' <> 'withdrawn'
 THEN RAISE EXCEPTION 'Withdrawn grant revived'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT total_registered_x_usernames FROM x_handle_registry.username_counts) <> 1
 OR (SELECT active_x_usernames_in_last_30_days FROM x_handle_registry.username_counts) <> 0
 OR EXISTS (SELECT FROM x_handle_registry.feedback_dm_eligible_handles)
 THEN RAISE EXCEPTION 'Withdrawal must preserve total and remove eligibility'; END IF;
END $$;

-- Use one transaction time so exactly 30 days is tested without clock drift.
BEGIN;
SELECT public.report_x_activity_v1('00000000-0000-0000-0000-000000000004', repeat('d',64), 'x-username-feedback-v1', 1, 'inside');
SELECT public.report_x_activity_v1('00000000-0000-0000-0000-000000000004', repeat('d',64), 'x-username-feedback-v1', 2, 'exact');
SELECT public.report_x_activity_v1('00000000-0000-0000-0000-000000000004', repeat('d',64), 'x-username-feedback-v1', 3, 'outside');
SELECT public.report_x_activity_v1('00000000-0000-0000-0000-000000000004', repeat('d',64), 'x-username-feedback-v1', 4, 'future');
UPDATE x_handle_registry.grant_handles SET last_activity_at = now() - interval '30 days' + interval '1 microsecond' WHERE handle='inside';
UPDATE x_handle_registry.grant_handles SET last_activity_at = now() - interval '30 days' WHERE handle='exact';
UPDATE x_handle_registry.grant_handles SET last_activity_at = now() - interval '30 days' - interval '1 microsecond' WHERE handle='outside';
UPDATE x_handle_registry.grant_handles SET last_activity_at = now() + interval '1 microsecond' WHERE handle='future';
DO $$ BEGIN
 IF (SELECT active_x_usernames_in_last_30_days FROM x_handle_registry.username_counts) <> 1 THEN
 RAISE EXCEPTION 'Strict 30-day boundary or future bound incorrect'; END IF;
END $$;
ROLLBACK;

SET ROLE anon;
DO $$
DECLARE bad text;
BEGIN
 FOREACH bad IN ARRAY ARRAY[NULL,'','@abc','ABC','a-b','café','abcdefghijklmnop','home','login','compose','settings',E'abc\n'] LOOP
  BEGIN
   PERFORM public.report_x_activity_v1('00000000-0000-0000-0000-000000000099', repeat('a',64), 'x-username-feedback-v1', 1, bad);
   RAISE EXCEPTION 'Invalid handle accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 FOREACH bad IN ARRAY ARRAY[NULL,'',repeat('a',63),repeat('a',65),repeat('z',64),repeat('A',64)] LOOP
  BEGIN
   PERFORM public.report_x_activity_v1('00000000-0000-0000-0000-000000000099', bad, 'x-username-feedback-v1', 1, 'valid');
   RAISE EXCEPTION 'Invalid capability accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
   PERFORM public.withdraw_x_sharing_v1('00000000-0000-0000-0000-000000000099', bad, 'x-username-feedback-v1');
   RAISE EXCEPTION 'Invalid withdrawal capability accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 BEGIN
  PERFORM public.report_x_activity_v1('00000000-0000-0000-0000-000000000001', repeat('b',64), 'x-username-feedback-v1', 2, 'valid');
  RAISE EXCEPTION 'Wrong capability accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.withdraw_x_sharing_v1('00000000-0000-0000-0000-000000000001', repeat('b',64), 'x-username-feedback-v1');
  RAISE EXCEPTION 'Wrong withdrawal capability accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 FOREACH bad IN ARRAY ARRAY[NULL,'old-version',''] LOOP
  BEGIN
   PERFORM public.report_x_activity_v1('00000000-0000-0000-0000-000000000099', repeat('a',64), bad, 1, 'valid');
   RAISE EXCEPTION 'Unknown disclosure accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
   PERFORM public.withdraw_x_sharing_v1('00000000-0000-0000-0000-000000000099', repeat('a',64), bad);
   RAISE EXCEPTION 'Unknown withdrawal disclosure accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 FOREACH bad IN ARRAY ARRAY[NULL,'0','-1'] LOOP
  BEGIN
   PERFORM public.report_x_activity_v1('00000000-0000-0000-0000-000000000099', repeat('a',64), 'x-username-feedback-v1', bad::bigint, 'valid');
   RAISE EXCEPTION 'Invalid sequence accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 BEGIN
  PERFORM public.report_x_activity_v1('00000000-0000-0000-0000-000000000099', repeat('a',64), 'x-username-feedback-v1', '9223372036854775808'::bigint, 'valid');
  RAISE EXCEPTION 'Overflow accepted';
 EXCEPTION WHEN numeric_value_out_of_range THEN NULL; END;
 BEGIN
  PERFORM public.register_x_handle('legacy'); RAISE EXCEPTION 'Legacy RPC still available';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM x_handle_registry.sharing_grants) <> 3
 OR (SELECT total_registered_x_usernames FROM x_handle_registry.username_counts) <> 1 THEN
 RAISE EXCEPTION 'Invalid calls changed the registry'; END IF;
END $$;

-- Both API roles are denied direct table operations and administrator views.
DO $$
DECLARE client text; relation text; operation text;
BEGIN
 FOREACH client IN ARRAY ARRAY['anon','authenticated'] LOOP
  EXECUTE format('SET LOCAL ROLE %I',client);
  FOREACH relation IN ARRAY ARRAY['sharing_grants','acknowledged_handles','grant_handles','username_counts','feedback_dm_eligible_handles','x_handle_registrations'] LOOP
   FOREACH operation IN ARRAY ARRAY['SELECT * FROM ','DELETE FROM ','UPDATE ','TRUNCATE ','INSERT INTO '] LOOP
    BEGIN
     EXECUTE operation || 'x_handle_registry.' || relation || CASE WHEN operation='UPDATE ' THEN ' SET handle = ''intruder''' WHEN operation='INSERT INTO ' THEN ' DEFAULT VALUES' ELSE '' END;
     RAISE EXCEPTION 'Client table operation allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
   END LOOP;
  END LOOP;
  EXECUTE 'RESET ROLE';
 END LOOP;
END $$;
SET ROLE authenticated;
DO $$ BEGIN
 BEGIN
  PERFORM public.withdraw_x_sharing_v1('00000000-0000-0000-0000-000000000099', repeat('a',64), 'x-username-feedback-v1');
  RAISE EXCEPTION 'Unapproved role has RPC execution';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF EXISTS (SELECT FROM pg_class WHERE oid IN ('x_handle_registry.sharing_grants'::regclass,'x_handle_registry.acknowledged_handles'::regclass,'x_handle_registry.grant_handles'::regclass) AND NOT relrowsecurity)
 OR (SELECT count(*) FROM pg_proc WHERE oid IN ('public.report_x_activity_v1(uuid,text,text,bigint,text)'::regprocedure,'public.withdraw_x_sharing_v1(uuid,text,text)'::regprocedure) AND prosecdef AND 'search_path=""'=ANY(proconfig)) <> 2 THEN
 RAISE EXCEPTION 'Missing RLS or secure function configuration'; END IF;
END $$;

-- Lost responses retry the same payload; reservation gaps never allow an older
-- sequence to create a new handle or refresh server activity.
BEGIN;
SET LOCAL ROLE anon;
SELECT public.report_x_activity_v1('00000000-0000-0000-0000-000000000020', repeat('f',64), 'x-username-feedback-v1', 1, 'retry_owner');
RESET ROLE;
CREATE TEMP TABLE retry_receipt AS
SELECT g.acknowledged_at, h.first_registered_at, gh.last_activity_at
FROM x_handle_registry.sharing_grants g
JOIN x_handle_registry.grant_handles gh USING (grant_id)
JOIN x_handle_registry.acknowledged_handles h USING (handle)
WHERE grant_id = '00000000-0000-0000-0000-000000000020';
SET LOCAL ROLE anon;
DO $$ BEGIN
 IF public.report_x_activity_v1('00000000-0000-0000-0000-000000000020', repeat('f',64), 'x-username-feedback-v1', 1, 'retry_owner')->>'status' <> 'duplicate' THEN
 RAISE EXCEPTION 'Lost response retry was not duplicate'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF EXISTS (
   SELECT g.acknowledged_at, h.first_registered_at, gh.last_activity_at
   FROM x_handle_registry.sharing_grants g
   JOIN x_handle_registry.grant_handles gh USING (grant_id)
   JOIN x_handle_registry.acknowledged_handles h USING (handle)
   WHERE grant_id = '00000000-0000-0000-0000-000000000020'
   EXCEPT SELECT * FROM retry_receipt
 ) THEN RAISE EXCEPTION 'Lost response retry changed a server timestamp'; END IF;
END $$;
SET LOCAL ROLE anon;
DO $$ BEGIN
 IF public.report_x_activity_v1('00000000-0000-0000-0000-000000000020', repeat('f',64), 'x-username-feedback-v1', 7, 'retry_owner')->>'status' <> 'recorded'
 OR public.report_x_activity_v1('00000000-0000-0000-0000-000000000020', repeat('f',64), 'x-username-feedback-v1', 6, 'stale_payload')->>'status' <> 'duplicate' THEN
 RAISE EXCEPTION 'Reservation gap or stale sequence rejected incorrectly'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF EXISTS (SELECT FROM x_handle_registry.acknowledged_handles WHERE handle='stale_payload')
 OR (SELECT highest_sequence FROM x_handle_registry.sharing_grants WHERE grant_id='00000000-0000-0000-0000-000000000020') <> 7
 OR (SELECT first_registered_at FROM x_handle_registry.acknowledged_handles WHERE handle='retry_owner') <> (SELECT first_registered_at FROM retry_receipt)
 THEN RAISE EXCEPTION 'Fresh activity rewrote registration or stale sequence mutated grant'; END IF;
END $$;
ROLLBACK;

-- Administrator fixtures supply exact database times and historical states.
-- Legacy rows, older disclosures, and unacknowledged grants never qualify.
BEGIN;
INSERT INTO x_handle_registry.x_handle_registrations(handle) VALUES ('legacy_only');
SELECT public.report_x_activity_v1('00000000-0000-0000-0000-000000000021', repeat('f',64), 'x-username-feedback-v1', 1, 'at_now');
SELECT public.report_x_activity_v1('00000000-0000-0000-0000-000000000022', repeat('f',64), 'x-username-feedback-v1', 1, 'old_disclosure');
SELECT public.report_x_activity_v1('00000000-0000-0000-0000-000000000023', repeat('f',64), 'x-username-feedback-v1', 1, 'unacknowledged');
UPDATE x_handle_registry.grant_handles SET last_activity_at=now();
UPDATE x_handle_registry.sharing_grants SET disclosure_version='fixture-previous-version' WHERE grant_id='00000000-0000-0000-0000-000000000022';
UPDATE x_handle_registry.sharing_grants SET acknowledged_at=NULL WHERE grant_id='00000000-0000-0000-0000-000000000023';
DO $$ BEGIN
 IF (SELECT total_registered_x_usernames FROM x_handle_registry.username_counts) <> 4
 OR (SELECT active_x_usernames_in_last_30_days FROM x_handle_registry.username_counts) <> 1
 OR (SELECT array_agg(handle ORDER BY handle) FROM x_handle_registry.feedback_dm_eligible_handles) IS DISTINCT FROM ARRAY['at_now']
 THEN RAISE EXCEPTION 'Current-version filtering, inclusive upper bound, or legacy exclusion failed'; END IF;
END $$;
ROLLBACK;

-- There is only one shipped disclosure. Simulate a successor's report contract
-- inside a rolled-back transaction, proving withdrawal still accepts v1,
-- including a grant whose first report never reached the database.
BEGIN;
SELECT public.report_x_activity_v1('00000000-0000-0000-0000-000000000024', repeat('f',64), 'x-username-feedback-v1', 1, 'before_upgrade');
DO $$ BEGIN
 EXECUTE replace(pg_get_functiondef('public.report_x_activity_v1(uuid,text,text,bigint,text)'::regprocedure),
                 'x-username-feedback-v1', 'fixture-successor-version');
END $$;
SET LOCAL ROLE anon;
DO $$
DECLARE id uuid;
BEGIN
 FOREACH id IN ARRAY ARRAY['00000000-0000-0000-0000-000000000024'::uuid,'00000000-0000-0000-0000-000000000025'::uuid] LOOP
  BEGIN
   PERFORM public.report_x_activity_v1(id, repeat('f',64), 'x-username-feedback-v1', 2, 'old_report');
   RAISE EXCEPTION 'Previous disclosure report accepted after version change';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  IF public.withdraw_x_sharing_v1(id, repeat('f',64), 'x-username-feedback-v1')->>'status' <> 'withdrawn' THEN
   RAISE EXCEPTION 'Previously supported disclosure cannot withdraw';
  END IF;
 END LOOP;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM x_handle_registry.sharing_grants WHERE grant_id IN ('00000000-0000-0000-0000-000000000024','00000000-0000-0000-0000-000000000025') AND withdrawn_at IS NOT NULL) <> 2
 OR (SELECT acknowledged_at IS NOT NULL FROM x_handle_registry.sharing_grants WHERE grant_id='00000000-0000-0000-0000-000000000025')
 OR EXISTS (SELECT FROM x_handle_registry.acknowledged_handles WHERE handle='old_report')
 THEN RAISE EXCEPTION 'Upgrade withdrawal failed to preserve grants and tombstones'; END IF;
END $$;
ROLLBACK;
