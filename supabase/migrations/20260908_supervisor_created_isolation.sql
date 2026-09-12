-- Metro Shift Roster: supervisor-created data isolation
-- No user/employee/station IDs are hardcoded.
-- Scope is always derived from the logged-in user's profile.

CREATE OR REPLACE FUNCTION public.rls_effective_supervisor_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
SET row_security TO 'off'
AS $function$
    SELECT CASE
        WHEN p.role::text = 'supervisor'
             AND COALESCE(p.is_reliever, false) = true
             AND p.parent_supervisor_id IS NOT NULL
          THEN p.parent_supervisor_id
        WHEN p.role::text = 'supervisor'
          THEN p.id
        WHEN p.role::text ILIKE '%operator%'
             AND p.parent_supervisor_id IS NOT NULL
          THEN p.parent_supervisor_id
        ELSE NULL
    END
    FROM public.profiles p
    WHERE p.id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.rls_my_operator(p_operator_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
SET row_security TO 'off'
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = p_operator_id
          AND p.role::text ILIKE '%operator%'
          AND p.parent_supervisor_id = public.rls_effective_supervisor_id()
    );
$function$;

-- Operators may read only their own profile plus operators created under
-- the same effective supervisor. This supplies roster names without
-- opening access to unrelated supervisors' staff.
DROP POLICY IF EXISTS profiles_operator_select ON public.profiles;
CREATE POLICY profiles_operator_select
ON public.profiles
FOR SELECT
TO authenticated
USING (
    (id = auth.uid())
    OR
    (
        rls_my_operator(id)
        AND id <> auth.uid()
    )
);

-- Operators may read only stations belonging to their effective supervisor.
DROP POLICY IF EXISTS stations_operator_select ON public.stations;
CREATE POLICY stations_operator_select
ON public.stations
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.profiles me
        WHERE me.id = auth.uid()
          AND me.role::text ILIKE '%operator%'
          AND me.org_id = stations.org_id
          AND me.parent_supervisor_id = public.rls_effective_supervisor_id()
          AND stations.supervisor_id = public.rls_effective_supervisor_id()
    )
);

-- Remove known broad read policies that bypass supervisor isolation.
DROP POLICY IF EXISTS "Allow read shifts" ON public.shifts;
DROP POLICY IF EXISTS "Supervisors and operators can view shifts" ON public.shifts;
DROP POLICY IF EXISTS "Allow read shift_assignments" ON public.shift_assignments;
DROP POLICY IF EXISTS "Allow authenticated users to view shift assignments" ON public.shift_assignments;
DROP POLICY IF EXISTS "Allow read stations" ON public.stations;
DROP POLICY IF EXISTS "Allow authenticated users to read stations" ON public.stations;

-- Published shifts: an operator sees only shifts created for their supervisor.
DROP POLICY IF EXISTS shifts_operator_select ON public.shifts;
CREATE POLICY shifts_operator_select
ON public.shifts
FOR SELECT
TO authenticated
USING (
    is_published = true
    AND EXISTS (
        SELECT 1
        FROM public.profiles me
        WHERE me.id = auth.uid()
          AND me.role::text ILIKE '%operator%'
          AND me.org_id = shifts.org_id
          AND me.parent_supervisor_id = public.rls_effective_supervisor_id()
          AND shifts.supervisor_id = public.rls_effective_supervisor_id()
    )
);

-- Supervisors/relievers see only shifts created under their effective supervisor.
DROP POLICY IF EXISTS shifts_supervisor_select ON public.shifts;
CREATE POLICY shifts_supervisor_select
ON public.shifts
FOR SELECT
TO authenticated
USING (
    rls_is_supervisor()
    AND supervisor_id = public.rls_effective_supervisor_id()
);

-- Assignment reads are scoped through the parent shift's supervisor.
DROP POLICY IF EXISTS "Operators view supervisor assignments" ON public.shift_assignments;
CREATE POLICY "Operators view supervisor assignments"
ON public.shift_assignments
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.shifts s
        JOIN public.profiles me ON me.id = auth.uid()
        WHERE s.id = shift_assignments.shift_id
          AND me.role::text ILIKE '%operator%'
          AND me.org_id = s.org_id
          AND me.parent_supervisor_id = public.rls_effective_supervisor_id()
          AND s.supervisor_id = public.rls_effective_supervisor_id()
          AND s.is_published = true
    )
);
