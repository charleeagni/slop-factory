-- Fresh acknowledged registry. Historical observations are deliberately excluded.
BEGIN;
CREATE TABLE x_handle_registry.sharing_grants (
    grant_id uuid PRIMARY KEY,
    capability_digest bytea NOT NULL CHECK (octet_length(capability_digest) = 32),
    disclosure_version text NOT NULL,
    acknowledged_at timestamptz,
    withdrawn_at timestamptz,
    highest_sequence bigint NOT NULL DEFAULT 0 CHECK (highest_sequence >= 0)
);
CREATE TABLE x_handle_registry.acknowledged_handles (
    handle text PRIMARY KEY CHECK (handle COLLATE "C" ~ '^[a-z0-9_]{1,15}$'),
    first_registered_at timestamptz NOT NULL
);
CREATE TABLE x_handle_registry.grant_handles (
    grant_id uuid NOT NULL REFERENCES x_handle_registry.sharing_grants,
    handle text NOT NULL REFERENCES x_handle_registry.acknowledged_handles,
    last_activity_at timestamptz NOT NULL,
    PRIMARY KEY (grant_id, handle)
);
ALTER TABLE x_handle_registry.sharing_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE x_handle_registry.acknowledged_handles ENABLE ROW LEVEL SECURITY;
ALTER TABLE x_handle_registry.grant_handles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA x_handle_registry FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SCHEMA x_handle_registry FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.register_x_handle(text) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.report_x_activity_v1(
    p_grant_id uuid, p_capability text, p_disclosure_version text,
    p_sequence bigint, p_handle text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    grant_row x_handle_registry.sharing_grants%ROWTYPE;
    receipt_time timestamptz;
    digest bytea;
BEGIN
    IF p_grant_id IS NULL OR p_capability IS NULL
       OR p_capability COLLATE "C" !~ '^[a-f0-9]{64}$'
       OR p_disclosure_version IS DISTINCT FROM 'x-username-feedback-v1'
       OR p_sequence IS NULL OR p_sequence <= 0
       OR p_handle IS NULL OR p_handle COLLATE "C" !~ '^[a-z0-9_]{1,15}$'
       OR p_handle = ANY (ARRAY[
           'about', 'account', 'accounts', 'compose', 'download', 'explore',
           'hashtag', 'home', 'i', 'intent', 'login', 'logout', 'messages',
           'notifications', 'privacy', 'search', 'settings', 'share', 'signup',
           'tos', 'help', 'jobs', 'oauth', 'premium', 'communities',
           'connect_people', 'who_to_follow', 'welcome'
       ]) THEN
        RAISE EXCEPTION 'Invalid activity inputs' USING ERRCODE = '22023';
    END IF;
    digest := pg_catalog.sha256(pg_catalog.decode(p_capability, 'hex'));
    INSERT INTO x_handle_registry.sharing_grants(grant_id, capability_digest, disclosure_version)
    VALUES (p_grant_id, digest, p_disclosure_version) ON CONFLICT DO NOTHING;
    SELECT * INTO STRICT grant_row FROM x_handle_registry.sharing_grants
    WHERE grant_id = p_grant_id FOR UPDATE;
    IF grant_row.capability_digest <> digest OR grant_row.disclosure_version <> p_disclosure_version THEN
        RAISE EXCEPTION 'Invalid grant credentials' USING ERRCODE = '22023';
    END IF;
    IF grant_row.withdrawn_at IS NOT NULL THEN
        RETURN pg_catalog.jsonb_build_object('status', 'withdrawn');
    END IF;
    IF p_sequence <= grant_row.highest_sequence THEN
        RETURN pg_catalog.jsonb_build_object('status', 'duplicate');
    END IF;
    receipt_time := pg_catalog.clock_timestamp();
    INSERT INTO x_handle_registry.acknowledged_handles(handle, first_registered_at)
    VALUES (p_handle, receipt_time) ON CONFLICT DO NOTHING;
    INSERT INTO x_handle_registry.grant_handles(grant_id, handle, last_activity_at)
    VALUES (p_grant_id, p_handle, receipt_time)
    ON CONFLICT (grant_id, handle) DO UPDATE SET last_activity_at = EXCLUDED.last_activity_at;
    UPDATE x_handle_registry.sharing_grants SET highest_sequence = p_sequence,
        acknowledged_at = COALESCE(acknowledged_at, receipt_time) WHERE grant_id = p_grant_id;
    RETURN pg_catalog.jsonb_build_object('status', 'recorded');
END;
$$;

CREATE FUNCTION public.withdraw_x_sharing_v1(
    p_grant_id uuid, p_capability text, p_disclosure_version text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    grant_row x_handle_registry.sharing_grants%ROWTYPE;
    digest bytea;
BEGIN
    -- Retain all supported versions here when a future report version is introduced.
    IF p_grant_id IS NULL OR p_capability IS NULL
       OR p_capability COLLATE "C" !~ '^[a-f0-9]{64}$'
       OR p_disclosure_version IS DISTINCT FROM 'x-username-feedback-v1' THEN
        RAISE EXCEPTION 'Invalid withdrawal inputs' USING ERRCODE = '22023';
    END IF;
    digest := pg_catalog.sha256(pg_catalog.decode(p_capability, 'hex'));
    INSERT INTO x_handle_registry.sharing_grants(grant_id, capability_digest, disclosure_version)
    VALUES (p_grant_id, digest, p_disclosure_version) ON CONFLICT DO NOTHING;
    SELECT * INTO STRICT grant_row FROM x_handle_registry.sharing_grants
    WHERE grant_id = p_grant_id FOR UPDATE;
    IF grant_row.capability_digest <> digest OR grant_row.disclosure_version <> p_disclosure_version THEN
        RAISE EXCEPTION 'Invalid grant credentials' USING ERRCODE = '22023';
    END IF;
    UPDATE x_handle_registry.sharing_grants
    SET withdrawn_at = COALESCE(withdrawn_at, pg_catalog.clock_timestamp())
    WHERE grant_id = p_grant_id;
    RETURN pg_catalog.jsonb_build_object('status', 'withdrawn');
END;
$$;
REVOKE ALL ON FUNCTION public.report_x_activity_v1(uuid,text,text,bigint,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.withdraw_x_sharing_v1(uuid,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.report_x_activity_v1(uuid,text,text,bigint,text) TO anon;
GRANT EXECUTE ON FUNCTION public.withdraw_x_sharing_v1(uuid,text,text) TO anon;

CREATE VIEW x_handle_registry.username_counts AS
SELECT (SELECT count(*) FROM x_handle_registry.acknowledged_handles) AS total_registered_x_usernames,
       (SELECT count(DISTINCT gh.handle)
        FROM x_handle_registry.grant_handles gh
        JOIN x_handle_registry.sharing_grants g USING (grant_id)
        WHERE g.withdrawn_at IS NULL AND g.acknowledged_at IS NOT NULL
          AND g.disclosure_version = 'x-username-feedback-v1'
          AND gh.last_activity_at > pg_catalog.now() - interval '30 days'
          AND gh.last_activity_at <= pg_catalog.now()) AS active_x_usernames_in_last_30_days;
CREATE VIEW x_handle_registry.feedback_dm_eligible_handles AS
SELECT DISTINCT gh.handle
FROM x_handle_registry.grant_handles gh JOIN x_handle_registry.sharing_grants g USING (grant_id)
WHERE g.withdrawn_at IS NULL AND g.acknowledged_at IS NOT NULL
  AND g.disclosure_version = 'x-username-feedback-v1';
REVOKE ALL ON x_handle_registry.username_counts, x_handle_registry.feedback_dm_eligible_handles FROM PUBLIC, anon, authenticated;
COMMIT;
