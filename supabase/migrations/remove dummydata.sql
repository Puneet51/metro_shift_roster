DO $$
DECLARE
    t text;
    target_tables text[] := ARRAY[
        'rosters',
        'shift_rosters',
        'shifts',
        'attendance',
        'attendances',
        'attendance_records',
        'leaves',
        'leave_requests',
        'swaps',
        'shift_swaps',
        'notifications',
        'user_notifications',
        'push_tokens'
    ];
BEGIN
    -- 1. Truncate only the operational tables that actually exist
    FOREACH t IN ARRAY target_tables
    LOOP
        IF EXISTS (
            SELECT 1 
            FROM information_schema.tables 
            WHERE table_schema = 'public' 
              AND table_name = t
        ) THEN
            EXECUTE format('TRUNCATE TABLE public.%I CASCADE;', t);
            RAISE NOTICE 'Truncated table: public.%', t;
        END IF;
    END LOOP;

    -- 2. Clear dummy users by casting role to text (protects all admin accounts regardless of casing)
    IF EXISTS (
        SELECT 1 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
          AND table_name = 'profiles'
    ) THEN
        DELETE FROM public.profiles 
        WHERE LOWER(role::text) NOT LIKE '%admin%';
        RAISE NOTICE 'Cleared non-admin profiles.';
    END IF;

    -- 3. Reset app versions to default initial state
    IF EXISTS (
        SELECT 1 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
          AND table_name = 'app_versions'
    ) THEN
        UPDATE public.app_versions
        SET 
            is_mandatory = false,
            force_update = false,
            version = '1.0.0',
            latest_version = '1.0.0',
            min_version = '1.0.0',
            min_supported_version = '1.0.0',
            release_notes = 'Initial release',
            description = 'Stable release',
            updated_at = NOW();
        RAISE NOTICE 'Reset app_versions configuration.';
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';

DO $$ 
DECLARE 
    r RECORD;
BEGIN
    -- 1. Truncate every user-created table in public schema except app_versions
    FOR r IN (
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public' 
          AND tablename NOT IN ('app_versions', 'schema_migrations')
    ) 
    LOOP
        EXECUTE format('TRUNCATE TABLE public.%I CASCADE;', r.tablename);
        RAISE NOTICE 'Truncated: %', r.tablename;
    END LOOP;

    -- 2. Clear Supabase Auth accounts (wipes logins, tokens, identities)
    TRUNCATE TABLE auth.identities CASCADE;
    TRUNCATE TABLE auth.users CASCADE;

    -- 3. Reset app_versions back to default initial state
    IF EXISTS (
        SELECT 1 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
          AND table_name = 'app_versions'
    ) THEN
        UPDATE public.app_versions
        SET 
            is_mandatory = false,
            force_update = false,
            version = '1.0.0',
            latest_version = '1.0.0',
            min_version = '1.0.0',
            min_supported_version = '1.0.0',
            release_notes = 'Initial release',
            description = 'Stable release',
            updated_at = NOW();
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';


SELECT 'profiles' AS table_name, count(*) FROM public.profiles
UNION ALL
SELECT 'users' AS table_name, count(*) FROM auth.users;