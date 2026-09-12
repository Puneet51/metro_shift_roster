BEGIN;

-- ============================================================
-- METRO SHIFT ROSTER
-- FINAL SUPERVISOR / OPERATOR ISOLATION
--
-- Admin:
--   Full access.
--
-- Supervisor A:
--   ONLY A's operators
--   ONLY A's stations
--   ONLY A's shifts
--   ONLY assignments involving A's operators / shifts
--   ONLY A's attendance / punch history
--
-- Operator Y:
--   ONLY Y's own profile, assignments, attendance,
--   punch sessions and notifications.
--
-- ============================================================


-- ============================================================
-- 1. ENABLE RLS
-- ============================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.station_operating_systems ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.station_shift_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shift_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.punch_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 2. HELPER FUNCTIONS
--
-- SECURITY DEFINER prevents these ownership checks from
-- recursively invoking the RLS policies.
-- ============================================================

CREATE OR REPLACE FUNCTION public.rls_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.role = 'admin'::user_role
    );
$$;


CREATE OR REPLACE FUNCTION public.rls_is_supervisor()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.role = 'supervisor'::user_role
    );
$$;


-- Does this operator belong to the logged-in supervisor?
CREATE OR REPLACE FUNCTION public.rls_my_operator(p_operator_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = p_operator_id
          AND p.role = 'operator'::user_role
          AND p.parent_supervisor_id = auth.uid()
    );
$$;


-- Does this station belong to the logged-in supervisor?
CREATE OR REPLACE FUNCTION public.rls_my_station(p_station_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.stations s
        WHERE s.id = p_station_id
          AND (
              s.supervisor_id = auth.uid()
              OR s.created_by = auth.uid()
          )
    );
$$;


-- Does this shift belong to the logged-in supervisor?
CREATE OR REPLACE FUNCTION public.rls_my_shift(p_shift_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.shifts s
        WHERE s.id = p_shift_id
          AND s.supervisor_id = auth.uid()
    );
$$;


-- Is this shift assigned to one of my operators?
CREATE OR REPLACE FUNCTION public.rls_shift_has_my_operator(p_shift_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.shift_assignments sa
        JOIN public.profiles p
          ON p.id = sa.operator_id
        WHERE sa.shift_id = p_shift_id
          AND p.parent_supervisor_id = auth.uid()
    );
$$;


-- ============================================================
-- 3. REMOVE ALL OLD POLICIES FROM THESE TABLES
-- ============================================================

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN (
              'profiles',
              'stations',
              'station_operating_systems',
              'station_shift_templates',
              'shifts',
              'shift_assignments',
              'attendance',
              'punch_sessions',
              'notifications'
          )
    LOOP
        EXECUTE format(
            'DROP POLICY IF EXISTS %I ON %I.%I',
            r.policyname,
            r.schemaname,
            r.tablename
        );
    END LOOP;
END
$$;


-- ============================================================
-- 4. PROFILES
-- ============================================================

CREATE POLICY profiles_admin_all
ON public.profiles
FOR ALL
TO authenticated
USING (public.rls_is_admin())
WITH CHECK (public.rls_is_admin());


-- Supervisor sees ONLY:
--   himself
--   operators created/owned by himself
CREATE POLICY profiles_supervisor_select
ON public.profiles
FOR SELECT
TO authenticated
USING (
    public.rls_is_supervisor()
    AND (
        id = auth.uid()
        OR public.rls_my_operator(id)
    )
);


-- Supervisor creates ONLY an operator belonging to himself.
CREATE POLICY profiles_supervisor_insert
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (
    public.rls_is_supervisor()
    AND role = 'operator'::user_role
    AND parent_supervisor_id = auth.uid()
    AND org_id = (
        SELECT p.org_id
        FROM public.profiles p
        WHERE p.id = auth.uid()
    )
);


-- Supervisor updates ONLY his own operators.
CREATE POLICY profiles_supervisor_update
ON public.profiles
FOR UPDATE
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_operator(id)
)
WITH CHECK (
    public.rls_is_supervisor()
    AND role = 'operator'::user_role
    AND parent_supervisor_id = auth.uid()
);


-- Supervisor deletes ONLY his own operators.
CREATE POLICY profiles_supervisor_delete
ON public.profiles
FOR DELETE
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_operator(id)
);


-- Operator reads ONLY himself.
CREATE POLICY profiles_operator_select
ON public.profiles
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.profiles me
        WHERE me.id = auth.uid()
          AND me.role = 'operator'::user_role
    )
    AND id = auth.uid()
);


-- Operator updates ONLY himself.
CREATE POLICY profiles_operator_update
ON public.profiles
FOR UPDATE
TO authenticated
USING (
    id = auth.uid()
    AND EXISTS (
        SELECT 1
        FROM public.profiles me
        WHERE me.id = auth.uid()
          AND me.role = 'operator'::user_role
    )
)
WITH CHECK (
    id = auth.uid()
);


-- ============================================================
-- 5. STATIONS
-- ============================================================

-- Admin can manage every station.
CREATE POLICY stations_admin_all
ON public.stations
FOR ALL
TO authenticated
USING (public.rls_is_admin())
WITH CHECK (public.rls_is_admin());


-- Supervisor can see ONLY stations belonging to him.
CREATE POLICY stations_supervisor_select
ON public.stations
FOR SELECT
TO authenticated
USING (
    public.rls_is_supervisor()
    AND (
        supervisor_id = auth.uid()
        OR created_by = auth.uid()
    )
);


-- Supervisor creates ONLY his own station.
CREATE POLICY stations_supervisor_insert
ON public.stations
FOR INSERT
TO authenticated
WITH CHECK (
    public.rls_is_supervisor()
    AND supervisor_id = auth.uid()
    AND created_by = auth.uid()
    AND org_id = (
        SELECT p.org_id
        FROM public.profiles p
        WHERE p.id = auth.uid()
    )
);


-- Supervisor updates ONLY his own station.
CREATE POLICY stations_supervisor_update
ON public.stations
FOR UPDATE
TO authenticated
USING (
    public.rls_is_supervisor()
    AND (
        supervisor_id = auth.uid()
        OR created_by = auth.uid()
    )
)
WITH CHECK (
    public.rls_is_supervisor()
    AND supervisor_id = auth.uid()
);


-- Supervisor deletes ONLY his own station.
CREATE POLICY stations_supervisor_delete
ON public.stations
FOR DELETE
TO authenticated
USING (
    public.rls_is_supervisor()
    AND (
        supervisor_id = auth.uid()
        OR created_by = auth.uid()
    )
);


-- ============================================================
-- 6. STATION OPERATING SYSTEMS
-- ============================================================

CREATE POLICY station_os_admin_all
ON public.station_operating_systems
FOR ALL
TO authenticated
USING (public.rls_is_admin())
WITH CHECK (public.rls_is_admin());


CREATE POLICY station_os_supervisor_all
ON public.station_operating_systems
FOR ALL
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_station(station_id)
)
WITH CHECK (
    public.rls_is_supervisor()
    AND public.rls_my_station(station_id)
);


-- ============================================================
-- 7. STATION SHIFT TEMPLATES
-- ============================================================

CREATE POLICY station_templates_admin_all
ON public.station_shift_templates
FOR ALL
TO authenticated
USING (public.rls_is_admin())
WITH CHECK (public.rls_is_admin());


CREATE POLICY station_templates_supervisor_all
ON public.station_shift_templates
FOR ALL
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_station(station_id)
)
WITH CHECK (
    public.rls_is_supervisor()
    AND public.rls_my_station(station_id)
);


-- ============================================================
-- 8. SHIFTS
-- ============================================================

CREATE POLICY shifts_admin_all
ON public.shifts
FOR ALL
TO authenticated
USING (public.rls_is_admin())
WITH CHECK (public.rls_is_admin());


-- Supervisor sees ONLY shifts he created/owns.
CREATE POLICY shifts_supervisor_all
ON public.shifts
FOR ALL
TO authenticated
USING (
    public.rls_is_supervisor()
    AND supervisor_id = auth.uid()
)
WITH CHECK (
    public.rls_is_supervisor()
    AND supervisor_id = auth.uid()
    AND org_id = (
        SELECT p.org_id
        FROM public.profiles p
        WHERE p.id = auth.uid()
    )
);


-- Operator sees ONLY shifts where he has an assignment.
CREATE POLICY shifts_operator_select
ON public.shifts
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.profiles me
        WHERE me.id = auth.uid()
          AND me.role = 'operator'::user_role
    )
    AND public.rls_shift_has_my_operator(id)
);


-- ============================================================
-- 9. SHIFT ASSIGNMENTS
-- ============================================================

CREATE POLICY assignments_admin_all
ON public.shift_assignments
FOR ALL
TO authenticated
USING (public.rls_is_admin())
WITH CHECK (public.rls_is_admin());


-- Supervisor can manage assignments ONLY when:
--   1. the shift belongs to him
--   OR
--   2. the operator belongs to him
CREATE POLICY assignments_supervisor_all
ON public.shift_assignments
FOR ALL
TO authenticated
USING (
    public.rls_is_supervisor()
    AND (
        public.rls_my_shift(shift_id)
        OR public.rls_my_operator(operator_id)
    )
)
WITH CHECK (
    public.rls_is_supervisor()
    AND (
        public.rls_my_shift(shift_id)
        AND public.rls_my_operator(operator_id)
    )
);


-- Operator can read ONLY his assignments.
CREATE POLICY assignments_operator_select
ON public.shift_assignments
FOR SELECT
TO authenticated
USING (
    operator_id = auth.uid()
);


-- ============================================================
-- 10. ATTENDANCE
-- ============================================================

CREATE POLICY attendance_admin_all
ON public.attendance
FOR ALL
TO authenticated
USING (public.rls_is_admin())
WITH CHECK (public.rls_is_admin());


-- Supervisor sees ONLY his operators' attendance.
CREATE POLICY attendance_supervisor_all
ON public.attendance
FOR ALL
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_operator(operator_id)
)
WITH CHECK (
    public.rls_is_supervisor()
    AND public.rls_my_operator(operator_id)
);


-- Operator sees ONLY his own attendance.
CREATE POLICY attendance_operator_select
ON public.attendance
FOR SELECT
TO authenticated
USING (
    operator_id = auth.uid()
);


CREATE POLICY attendance_operator_insert
ON public.attendance
FOR INSERT
TO authenticated
WITH CHECK (
    operator_id = auth.uid()
);


CREATE POLICY attendance_operator_update
ON public.attendance
FOR UPDATE
TO authenticated
USING (
    operator_id = auth.uid()
)
WITH CHECK (
    operator_id = auth.uid()
);


-- ============================================================
-- 11. PUNCH SESSIONS
-- ============================================================

CREATE POLICY punches_admin_all
ON public.punch_sessions
FOR ALL
TO authenticated
USING (public.rls_is_admin())
WITH CHECK (public.rls_is_admin());


-- Supervisor sees ONLY punches from his operators.
CREATE POLICY punches_supervisor_all
ON public.punch_sessions
FOR ALL
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_operator(operator_id)
)
WITH CHECK (
    public.rls_is_supervisor()
    AND public.rls_my_operator(operator_id)
);


-- Operator sees ONLY own punches.
CREATE POLICY punches_operator_select
ON public.punch_sessions
FOR SELECT
TO authenticated
USING (
    operator_id = auth.uid()
);


CREATE POLICY punches_operator_insert
ON public.punch_sessions
FOR INSERT
TO authenticated
WITH CHECK (
    operator_id = auth.uid()
);


CREATE POLICY punches_operator_update
ON public.punch_sessions
FOR UPDATE
TO authenticated
USING (
    operator_id = auth.uid()
)
WITH CHECK (
    operator_id = auth.uid()
);


-- ============================================================
-- 12. NOTIFICATIONS
-- ============================================================

-- User can read ONLY own notifications.
CREATE POLICY notifications_owner_select
ON public.notifications
FOR SELECT
TO authenticated
USING (
    user_id = auth.uid()
);


-- User can mark ONLY own notifications.
CREATE POLICY notifications_owner_update
ON public.notifications
FOR UPDATE
TO authenticated
USING (
    user_id = auth.uid()
)
WITH CHECK (
    user_id = auth.uid()
);


-- Admin/supervisor may manually insert notifications.
-- Your SECURITY DEFINER notification trigger is unaffected.
CREATE POLICY notifications_admin_supervisor_insert
ON public.notifications
FOR INSERT
TO authenticated
WITH CHECK (
    (
        public.rls_is_admin()
        OR public.rls_is_supervisor()
    )
    AND org_id = (
        SELECT p.org_id
        FROM public.profiles p
        WHERE p.id = auth.uid()
    )
);


COMMIT;


BEGIN;

-- ============================================================
-- FIX RLS RECURSION
-- Helper functions must bypass RLS for internal ownership checks.
-- ============================================================

CREATE OR REPLACE FUNCTION public.rls_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.role = 'admin'::user_role
    );
$$;


CREATE OR REPLACE FUNCTION public.rls_is_supervisor()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.role = 'supervisor'::user_role
    );
$$;


CREATE OR REPLACE FUNCTION public.rls_my_operator(p_operator_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = p_operator_id
          AND p.role = 'operator'::user_role
          AND p.parent_supervisor_id = auth.uid()
    );
$$;


CREATE OR REPLACE FUNCTION public.rls_my_station(p_station_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.stations s
        WHERE s.id = p_station_id
          AND (
              s.supervisor_id = auth.uid()
              OR s.created_by = auth.uid()
          )
    );
$$;


CREATE OR REPLACE FUNCTION public.rls_my_shift(p_shift_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.shifts s
        WHERE s.id = p_shift_id
          AND s.supervisor_id = auth.uid()
    );
$$;


CREATE OR REPLACE FUNCTION public.rls_shift_has_my_operator(p_shift_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.shift_assignments sa
        JOIN public.profiles p
          ON p.id = sa.operator_id
        WHERE sa.shift_id = p_shift_id
          AND p.parent_supervisor_id = auth.uid()
    );
$$;


-- Make absolutely sure these functions are owned by postgres,
-- which is the normal Supabase SQL Editor owner and can bypass RLS.
ALTER FUNCTION public.rls_is_admin() OWNER TO postgres;
ALTER FUNCTION public.rls_is_supervisor() OWNER TO postgres;
ALTER FUNCTION public.rls_my_operator(uuid) OWNER TO postgres;
ALTER FUNCTION public.rls_my_station(uuid) OWNER TO postgres;
ALTER FUNCTION public.rls_my_shift(uuid) OWNER TO postgres;
ALTER FUNCTION public.rls_shift_has_my_operator(uuid) OWNER TO postgres;


COMMIT;



BEGIN;

-- ============================================================
-- EFFECTIVE SUPERVISOR
--
-- Normal supervisor:
--   returns own ID
--
-- Reliever:
--   returns primary supervisor ID from parent_supervisor_id
-- ============================================================

CREATE OR REPLACE FUNCTION public.rls_effective_supervisor_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT
        CASE
            WHEN p.role = 'supervisor'::user_role
                 AND COALESCE(p.is_reliever, false) = true
            THEN p.parent_supervisor_id
            WHEN p.role = 'supervisor'::user_role
            THEN p.id
            ELSE NULL
        END
    FROM public.profiles p
    WHERE p.id = auth.uid();
$$;

ALTER FUNCTION public.rls_effective_supervisor_id()
OWNER TO postgres;


-- ============================================================
-- SUPERVISOR / RELIEVER CHECK
-- ============================================================

CREATE OR REPLACE FUNCTION public.rls_is_supervisor()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.role = 'supervisor'::user_role
    );
$$;

ALTER FUNCTION public.rls_is_supervisor()
OWNER TO postgres;


-- ============================================================
-- OPERATOR BELONGS TO CURRENT SUPERVISOR
-- Works for both:
--
-- Supervisor A:
--   parent_supervisor_id = A
--
-- Reliever R of A:
--   parent_supervisor_id = A
-- ============================================================

CREATE OR REPLACE FUNCTION public.rls_my_operator(
    p_operator_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = p_operator_id
          AND p.role = 'operator'::user_role
          AND p.parent_supervisor_id =
              public.rls_effective_supervisor_id()
    );
$$;

ALTER FUNCTION public.rls_my_operator(uuid)
OWNER TO postgres;


-- ============================================================
-- STATION BELONGS TO CURRENT SUPERVISOR
-- ============================================================

CREATE OR REPLACE FUNCTION public.rls_my_station(
    p_station_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.stations s
        WHERE s.id = p_station_id
          AND (
              s.supervisor_id =
                  public.rls_effective_supervisor_id()
              OR
              s.created_by =
                  public.rls_effective_supervisor_id()
          )
    );
$$;

ALTER FUNCTION public.rls_my_station(uuid)
OWNER TO postgres;


-- ============================================================
-- SHIFT BELONGS TO CURRENT SUPERVISOR
-- ============================================================

CREATE OR REPLACE FUNCTION public.rls_my_shift(
    p_shift_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.shifts s
        WHERE s.id = p_shift_id
          AND s.supervisor_id =
              public.rls_effective_supervisor_id()
    );
$$;

ALTER FUNCTION public.rls_my_shift(uuid)
OWNER TO postgres;


-- ============================================================
-- SHIFT HAS AN OPERATOR OF CURRENT SUPERVISOR
-- ============================================================

CREATE OR REPLACE FUNCTION public.rls_shift_has_my_operator(
    p_shift_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.shift_assignments sa
        JOIN public.profiles p
          ON p.id = sa.operator_id
        WHERE sa.shift_id = p_shift_id
          AND p.role = 'operator'::user_role
          AND p.parent_supervisor_id =
              public.rls_effective_supervisor_id()
    );
$$;

ALTER FUNCTION public.rls_shift_has_my_operator(uuid)
OWNER TO postgres;


-- ============================================================
-- RECREATE SUPERVISOR PROFILE POLICIES
-- ============================================================

DROP POLICY IF EXISTS profiles_supervisor_select
ON public.profiles;

CREATE POLICY profiles_supervisor_select
ON public.profiles
FOR SELECT
TO authenticated
USING (
    public.rls_is_supervisor()
    AND (
        id = auth.uid()
        OR public.rls_my_operator(id)
    )
);


DROP POLICY IF EXISTS profiles_supervisor_insert
ON public.profiles;

CREATE POLICY profiles_supervisor_insert
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (
    public.rls_is_supervisor()
    AND role = 'operator'::user_role
    AND parent_supervisor_id =
        public.rls_effective_supervisor_id()
    AND org_id = (
        SELECT p.org_id
        FROM public.profiles p
        WHERE p.id =
            public.rls_effective_supervisor_id()
    )
);


DROP POLICY IF EXISTS profiles_supervisor_update
ON public.profiles;

CREATE POLICY profiles_supervisor_update
ON public.profiles
FOR UPDATE
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_operator(id)
)
WITH CHECK (
    public.rls_is_supervisor()
    AND role = 'operator'::user_role
    AND parent_supervisor_id =
        public.rls_effective_supervisor_id()
);


DROP POLICY IF EXISTS profiles_supervisor_delete
ON public.profiles;

CREATE POLICY profiles_supervisor_delete
ON public.profiles
FOR DELETE
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_operator(id)
);


-- ============================================================
-- STATIONS
-- ============================================================

DROP POLICY IF EXISTS stations_supervisor_select
ON public.stations;

CREATE POLICY stations_supervisor_select
ON public.stations
FOR SELECT
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_station(id)
);


DROP POLICY IF EXISTS stations_supervisor_insert
ON public.stations;

CREATE POLICY stations_supervisor_insert
ON public.stations
FOR INSERT
TO authenticated
WITH CHECK (
    public.rls_is_supervisor()
    AND supervisor_id =
        public.rls_effective_supervisor_id()
    AND created_by = auth.uid()
    AND org_id = (
        SELECT p.org_id
        FROM public.profiles p
        WHERE p.id =
            public.rls_effective_supervisor_id()
    )
);


DROP POLICY IF EXISTS stations_supervisor_update
ON public.stations;

CREATE POLICY stations_supervisor_update
ON public.stations
FOR UPDATE
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_station(id)
)
WITH CHECK (
    public.rls_is_supervisor()
    AND supervisor_id =
        public.rls_effective_supervisor_id()
);


DROP POLICY IF EXISTS stations_supervisor_delete
ON public.stations;

CREATE POLICY stations_supervisor_delete
ON public.stations
FOR DELETE
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_station(id)
);


-- ============================================================
-- STATION OPERATING SYSTEMS
-- ============================================================

DROP POLICY IF EXISTS station_os_supervisor_all
ON public.station_operating_systems;

CREATE POLICY station_os_supervisor_all
ON public.station_operating_systems
FOR ALL
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_station(station_id)
)
WITH CHECK (
    public.rls_is_supervisor()
    AND public.rls_my_station(station_id)
);


-- ============================================================
-- STATION SHIFT TEMPLATES
-- ============================================================

DROP POLICY IF EXISTS station_templates_supervisor_all
ON public.station_shift_templates;

CREATE POLICY station_templates_supervisor_all
ON public.station_shift_templates
FOR ALL
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_station(station_id)
)
WITH CHECK (
    public.rls_is_supervisor()
    AND public.rls_my_station(station_id)
);


-- ============================================================
-- SHIFTS
-- ============================================================

DROP POLICY IF EXISTS shifts_supervisor_all
ON public.shifts;

CREATE POLICY shifts_supervisor_all
ON public.shifts
FOR ALL
TO authenticated
USING (
    public.rls_is_supervisor()
    AND supervisor_id =
        public.rls_effective_supervisor_id()
)
WITH CHECK (
    public.rls_is_supervisor()
    AND supervisor_id =
        public.rls_effective_supervisor_id()
    AND org_id = (
        SELECT p.org_id
        FROM public.profiles p
        WHERE p.id =
            public.rls_effective_supervisor_id()
    )
);


-- ============================================================
-- SHIFT ASSIGNMENTS
-- ============================================================

DROP POLICY IF EXISTS assignments_supervisor_all
ON public.shift_assignments;

CREATE POLICY assignments_supervisor_all
ON public.shift_assignments
FOR ALL
TO authenticated
USING (
    public.rls_is_supervisor()
    AND (
        public.rls_my_shift(shift_id)
        OR public.rls_my_operator(operator_id)
    )
)
WITH CHECK (
    public.rls_is_supervisor()
    AND public.rls_my_shift(shift_id)
    AND public.rls_my_operator(operator_id)
);


-- ============================================================
-- ATTENDANCE
-- ============================================================

DROP POLICY IF EXISTS attendance_supervisor_all
ON public.attendance;

CREATE POLICY attendance_supervisor_all
ON public.attendance
FOR ALL
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_operator(operator_id)
)
WITH CHECK (
    public.rls_is_supervisor()
    AND public.rls_my_operator(operator_id)
);


-- ============================================================
-- PUNCH SESSIONS
-- ============================================================

DROP POLICY IF EXISTS punches_supervisor_all
ON public.punch_sessions;

CREATE POLICY punches_supervisor_all
ON public.punch_sessions
FOR ALL
TO authenticated
USING (
    public.rls_is_supervisor()
    AND public.rls_my_operator(operator_id)
)
WITH CHECK (
    public.rls_is_supervisor()
    AND public.rls_my_operator(operator_id)
);


COMMIT;