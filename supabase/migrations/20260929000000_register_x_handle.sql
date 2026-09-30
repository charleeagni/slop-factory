-- Client-reported observations only; this registry is not proof of X ownership.
BEGIN;
CREATE SCHEMA IF NOT EXISTS x_handle_registry;
CREATE TABLE x_handle_registry.x_handle_registrations (
    handle text PRIMARY KEY CHECK (handle COLLATE "C" ~ '^[a-z0-9_]{1,15}$'),
    first_seen_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);
ALTER TABLE x_handle_registry.x_handle_registrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON SCHEMA x_handle_registry FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE x_handle_registry.x_handle_registrations FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.register_x_handle(p_handle text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF p_handle IS NULL OR p_handle COLLATE "C" !~ '^[A-Za-z0-9_]{1,15}$'
       OR pg_catalog.lower(p_handle) = ANY (ARRAY[
           'about', 'account', 'accounts', 'compose', 'download', 'explore',
           'hashtag', 'home', 'i', 'intent', 'login', 'logout', 'messages',
           'notifications', 'privacy', 'search', 'settings', 'share', 'signup',
           'tos', 'help', 'jobs', 'oauth', 'premium', 'communities',
           'connect_people', 'who_to_follow', 'welcome'
       ]) THEN
        RAISE EXCEPTION 'Invalid X handle' USING ERRCODE = '22023';
    END IF;
    INSERT INTO x_handle_registry.x_handle_registrations (handle)
    VALUES (pg_catalog.lower(p_handle))
    ON CONFLICT (handle) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.register_x_handle(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_x_handle(text) TO anon;
COMMIT;
