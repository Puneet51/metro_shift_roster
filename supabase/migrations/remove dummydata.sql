-- Disable triggers temporarily to prevent foreign key constraint order issues
SET session_replication_role = 'replica';

-- 1. Wipe test attendance and punch sessions
TRUNCATE TABLE public.attendance RESTART IDENTITY CASCADE;

-- 2. Wipe test shifts and shift assignments
TRUNCATE TABLE public.shift_assignments RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.shifts RESTART IDENTITY CASCADE;

-- 3. Wipe test notifications
TRUNCATE TABLE public.notifications RESTART IDENTITY CASCADE;

-- wipe test stastion 
TRUNCATE TABLE public.stations RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.station_shift_templates RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.station_operating_systems RESTART IDENTITY CASCADE;

-- 4. Wipe test leaves and week-offs (if tables exist)
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'leaves') THEN
    TRUNCATE TABLE public.leaves RESTART IDENTITY CASCADE;
  END IF;
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'week_offs') THEN
    TRUNCATE TABLE public.week_offs RESTART IDENTITY CASCADE;
  END IF;
END $$;

-- 5. Wipe test operators/profiles (Preserving Admins)
DELETE FROM public.profiles
WHERE role != 'admin';

-- Re-enable normal trigger execution and constraints
SET session_replication_role = 'origin';


SET session_replication_role = 'replica';

-- Clean non-admin test accounts out of auth.users
DELETE FROM auth.users
WHERE id NOT IN (
    SELECT id FROM public.profiles WHERE role = 'admin'
);

DELETE FROM public.profiles
WHERE role != 'admin';

SET session_replication_role = 'origin';



-- verify data deleted or not
SELECT 'attendance' AS table_name, count(*) AS total_rows FROM public.attendance
UNION ALL
SELECT 'shift_assignments', count(*) FROM public.shift_assignments
UNION ALL
SELECT 'shifts', count(*) FROM public.shifts
UNION ALL
SELECT 'notifications', count(*) FROM public.notifications
UNION ALL
SELECT 'profiles (non-admin)', count(*) FROM public.profiles WHERE role != 'admin'
UNION ALL
SELECT 'profiles (admin preserved)', count(*) FROM public.profiles WHERE role = 'admin'
UNION ALL
SELECT 'stations (preserved)', count(*) FROM public.stations
UNION ALL
SELECT 'app_versions (preserved)', count(*) FROM public.app_versions;