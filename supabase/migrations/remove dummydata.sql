-- ============================================================
-- METRO SHIFT ROSTER — COMPLETE TEST DATA CLEANUP
-- ============================================================
-- Deletes ALL TEST DATA, including admin accounts.
--
-- PRESERVES:
--   - Tables / schema
--   - RLS policies
--   - RPC / functions
--   - Cron jobs
--   - attendance_status enum including week_off
--   - PostGIS configuration
--
-- WARNING:
--   This deletes ALL profiles and ALL auth users.
--   Use ONLY on a disposable/test database.
-- ============================================================

BEGIN;

-- Temporarily disable triggers/foreign-key enforcement
-- for this cleanup session only.
SET LOCAL session_replication_role = 'replica';


-- ------------------------------------------------------------
-- 1. Attendance / punch data
-- ------------------------------------------------------------

TRUNCATE TABLE public.attendance RESTART IDENTITY CASCADE;

TRUNCATE TABLE public.punch_sessions RESTART IDENTITY CASCADE;


-- ------------------------------------------------------------
-- 2. Shift / duty data
-- ------------------------------------------------------------

TRUNCATE TABLE public.shift_assignments RESTART IDENTITY CASCADE;

TRUNCATE TABLE public.shifts RESTART IDENTITY CASCADE;


-- ------------------------------------------------------------
-- 3. Station-related test data
-- ------------------------------------------------------------

TRUNCATE TABLE public.station_shift_templates
RESTART IDENTITY CASCADE;

TRUNCATE TABLE public.station_operating_systems
RESTART IDENTITY CASCADE;

TRUNCATE TABLE public.stations
RESTART IDENTITY CASCADE;


-- ------------------------------------------------------------
-- 4. Notifications
-- ------------------------------------------------------------

TRUNCATE TABLE public.notifications RESTART IDENTITY CASCADE;


-- ------------------------------------------------------------
-- 5. Optional leave / week-off tables
-- ------------------------------------------------------------

DO $$
BEGIN

    IF to_regclass('public.leaves') IS NOT NULL THEN
        TRUNCATE TABLE public.leaves RESTART IDENTITY CASCADE;
    END IF;

    IF to_regclass('public.week_offs') IS NOT NULL THEN
        TRUNCATE TABLE public.week_offs RESTART IDENTITY CASCADE;
    END IF;

END
$$;


-- ------------------------------------------------------------
-- 6. Delete ALL application profiles
-- ------------------------------------------------------------

DELETE FROM public.profiles;


-- ------------------------------------------------------------
-- 7. Delete ALL Supabase Auth users
-- ------------------------------------------------------------

DELETE FROM auth.users;


-- Restore normal trigger/constraint behavior
SET LOCAL session_replication_role = 'origin';

COMMIT;


-- ============================================================
-- VERIFY
-- ============================================================

SELECT 'profiles' AS table_name, COUNT(*) AS remaining_rows
FROM public.profiles

UNION ALL

SELECT 'auth.users', COUNT(*)
FROM auth.users

UNION ALL

SELECT 'attendance', COUNT(*)
FROM public.attendance

UNION ALL

SELECT 'punch_sessions', COUNT(*)
FROM public.punch_sessions

UNION ALL

SELECT 'shift_assignments', COUNT(*)
FROM public.shift_assignments

UNION ALL

SELECT 'shifts', COUNT(*)
FROM public.shifts

UNION ALL

SELECT 'stations', COUNT(*)
FROM public.stations

UNION ALL

SELECT 'notifications', COUNT(*)
FROM public.notifications;





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