-- ============================================================
-- METRO SHIFT ROSTER — ATTENDANCE FINALIZATION PATCH
-- ============================================================
-- Rules:
--   PRESENT: 7h 50m through 10h
--   ABSENT: below 7h 50m
--   ABSENT: forgotten punch-out at 10h
--   ABSENT: no punch-in by assigned shift end
--   ABSENT: no punch-in by end of calendar duty date when unassigned
--
-- Does NOT change RLS policies.
-- Run this in Supabase SQL Editor.
-- ============================================================

CREATE OR REPLACE FUNCTION public.process_punch_in(
    p_station_id uuid,
    p_lat double precision,
    p_lng double precision,
    p_face_embedding jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_operator_id uuid := auth.uid();
    v_org_id uuid;
    v_station public.stations%ROWTYPE;
    v_distance double precision;
    v_assigned_shift_id uuid;
    v_duty_date date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
    v_last_punch_out timestamptz;
    v_session_id uuid;
    v_status public.punch_status := 'in_progress';
    v_face jsonb;
    v_punch_in timestamptz := now();
BEGIN
    IF v_operator_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    SELECT org_id
    INTO v_org_id
    FROM public.profiles
    WHERE id = v_operator_id
      AND is_active = true;

    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'Operator profile not found or inactive.';
    END IF;

    v_face := public.verify_registered_face_embedding(v_operator_id, p_face_embedding);

    IF COALESCE((v_face ->> 'matched')::boolean, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'Face verification failed. The face does not match the registered account.';
    END IF;

    SELECT *
    INTO v_station
    FROM public.stations
    WHERE id = p_station_id
      AND org_id = v_org_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Station not found.';
    END IF;

    v_distance := ST_Distance(
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(v_station.longitude, v_station.latitude), 4326)::geography
    );

    IF v_distance > v_station.punch_radius_meters THEN
        RAISE EXCEPTION
            'You are outside the permitted station radius (% meters away, allowed %m).',
            round(v_distance::numeric, 1),
            v_station.punch_radius_meters;
    END IF;

    SELECT punch_out_at
    INTO v_last_punch_out
    FROM public.punch_sessions
    WHERE operator_id = v_operator_id
      AND punch_out_at IS NOT NULL
    ORDER BY punch_out_at DESC
    LIMIT 1;

    IF v_last_punch_out IS NOT NULL
       AND (now() - v_last_punch_out) < interval '1 hour' THEN
        RAISE EXCEPTION 'Re-punch not allowed within 1 hour of previous punch out.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.punch_sessions
        WHERE operator_id = v_operator_id
          AND punch_out_at IS NULL
    ) THEN
        RAISE EXCEPTION 'You already have an active punch-in session.';
    END IF;

    SELECT s.id
    INTO v_assigned_shift_id
    FROM public.shifts s
    JOIN public.shift_assignments sa
      ON sa.shift_id = s.id
    WHERE sa.operator_id = v_operator_id
      AND s.station_id = p_station_id
      AND s.duty_date = v_duty_date
      AND s.is_published = true
    ORDER BY s.end_time DESC
    LIMIT 1;

    IF v_assigned_shift_id IS NULL THEN
        v_status := 'unassigned_pending';
    END IF;

    INSERT INTO public.punch_sessions (
        org_id,
        operator_id,
        station_id,
        shift_id,
        duty_date,
        punch_in_at,
        punch_in_lat,
        punch_in_lng,
        punch_in_verified,
        status,
        is_face_verified,
        updated_at
    )
    VALUES (
        v_org_id,
        v_operator_id,
        p_station_id,
        v_assigned_shift_id,
        v_duty_date,
        v_punch_in,
        p_lat,
        p_lng,
        true,
        v_status,
        true,
        v_punch_in
    )
    RETURNING id INTO v_session_id;

    -- Create exactly one attendance row at punch-in.
    -- It remains ABSENT until a valid punch-out changes it to PRESENT.
    INSERT INTO public.attendance (
        org_id,
        operator_id,
        station_id,
        shift_id,
        punch_session_id,
        session_id,
        duty_date,
        status,
        is_ot,
        earnings,
        punch_in_time,
        punch_in_lat,
        punch_in_lng,
        face_confidence,
        updated_at
    )
    VALUES (
        v_org_id,
        v_operator_id,
        p_station_id,
        v_assigned_shift_id,
        v_session_id,
        v_session_id,
        v_duty_date,
        'absent',
        COALESCE((
            SELECT sa.is_ot
            FROM public.shift_assignments sa
            WHERE sa.shift_id = v_assigned_shift_id
              AND sa.operator_id = v_operator_id
            LIMIT 1
        ), false),
        0.00,
        v_punch_in,
        p_lat,
        p_lng,
        COALESCE((v_face ->> 'similarity')::double precision, 1.0),
        v_punch_in
    );

    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'status', v_status,
        'duty_date', v_duty_date,
        'face_similarity', v_face -> 'similarity',
        'assigned', (v_assigned_shift_id IS NOT NULL)
    );
END;
$function$;


CREATE OR REPLACE FUNCTION public.process_punch_out(
    p_session_id uuid,
    p_lat double precision,
    p_lng double precision,
    p_face_embedding jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_session public.punch_sessions%ROWTYPE;
    v_station public.stations%ROWTYPE;
    v_distance double precision;
    v_duty_seconds integer;
    v_hours_worked numeric(10,2);
    v_fixed_amount numeric(10,2) := 0.00;
    v_is_ot boolean := false;
    v_face jsonb;
    v_status text;
    v_earnings numeric(10,2) := 0.00;
    v_punch_out timestamptz := now();
    v_attendance_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    SELECT *
    INTO v_session
    FROM public.punch_sessions
    WHERE id = p_session_id
      AND operator_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active punch session not found.';
    END IF;

    IF v_session.punch_out_at IS NOT NULL THEN
        RAISE EXCEPTION 'Punch out already recorded for this session.';
    END IF;

    v_face := public.verify_registered_face_embedding(auth.uid(), p_face_embedding);

    IF COALESCE((v_face ->> 'matched')::boolean, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'Face verification failed. The face does not match the registered account.';
    END IF;

    SELECT *
    INTO v_station
    FROM public.stations
    WHERE id = v_session.station_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Station not found.';
    END IF;

    v_distance := ST_Distance(
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(v_station.longitude, v_station.latitude), 4326)::geography
    );

    IF v_distance > v_station.punch_radius_meters THEN
        RAISE EXCEPTION 'You are outside the permitted station radius for punch out.';
    END IF;

    v_duty_seconds := greatest(0, round(extract(epoch FROM (v_punch_out - v_session.punch_in_at)))::integer);
    v_hours_worked := round((v_duty_seconds / 3600.0)::numeric, 2);

    IF v_duty_seconds >= 36000 THEN
        v_status := 'absent';
    ELSIF v_duty_seconds >= 28200 THEN
        v_status := 'present';
    ELSE
        v_status := 'absent';
    END IF;

    IF v_session.shift_id IS NOT NULL THEN
        SELECT s.daily_amount
        INTO v_fixed_amount
        FROM public.shifts s
        WHERE s.id = v_session.shift_id;

        SELECT COALESCE(sa.is_ot, false)
        INTO v_is_ot
        FROM public.shift_assignments sa
        WHERE sa.shift_id = v_session.shift_id
          AND sa.operator_id = auth.uid()
        LIMIT 1;
    ELSE
        SELECT COALESCE(default_fixed_amount, 0.00)
        INTO v_fixed_amount
        FROM public.stations
        WHERE id = v_session.station_id;
    END IF;

    IF v_status = 'present' AND NOT v_is_ot THEN
        v_earnings := COALESCE(v_fixed_amount, 0.00);
    END IF;

    UPDATE public.punch_sessions
    SET
        punch_out_at = v_punch_out,
        punch_out_lat = p_lat,
        punch_out_lng = p_lng,
        punch_out_verified = true,
        status = 'completed'::punch_status,
        updated_at = v_punch_out
    WHERE id = p_session_id
      AND operator_id = auth.uid()
      AND punch_out_at IS NULL;

    UPDATE public.attendance
    SET
        punch_out_time = v_punch_out,
        punch_out_lat = p_lat,
        punch_out_lng = p_lng,
        duty_duration_seconds = v_duty_seconds,
        total_hours = v_hours_worked,
        status = v_status,
        earnings = v_earnings,
        punch_out_accuracy = NULL,
        updated_at = v_punch_out
    WHERE punch_session_id = p_session_id
    RETURNING id INTO v_attendance_id;

    IF v_attendance_id IS NULL THEN
        INSERT INTO public.attendance (
            org_id,
            operator_id,
            station_id,
            shift_id,
            punch_session_id,
            session_id,
            duty_date,
            status,
            is_ot,
            earnings,
            punch_in_time,
            punch_out_time,
            duty_duration_seconds,
            total_hours,
            punch_out_lat,
            punch_out_lng,
            updated_at
        )
        VALUES (
            v_session.org_id,
            v_session.operator_id,
            v_session.station_id,
            v_session.shift_id,
            p_session_id,
            p_session_id,
            v_session.duty_date,
            v_status,
            v_is_ot,
            v_earnings,
            v_session.punch_in_at,
            v_punch_out,
            v_duty_seconds,
            v_hours_worked,
            p_lat,
            p_lng,
            v_punch_out
        )
        RETURNING id INTO v_attendance_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'session_id', p_session_id,
        'attendance_id', v_attendance_id,
        'duty_date', v_session.duty_date,
        'hours_worked', v_hours_worked,
        'duration_seconds', v_duty_seconds,
        'status', v_status,
        'earnings_credited', v_earnings,
        'is_ot', v_is_ot,
        'message', CASE
            WHEN v_duty_seconds >= 36000 THEN
                'Punch Out recorded at the maximum 10-hour limit. Attendance marked ABSENT.'
            WHEN v_status = 'present' THEN
                'Punch Out recorded successfully. Attendance marked PRESENT.'
            ELSE
                'Punch Out recorded successfully. Attendance marked ABSENT because minimum required duty is 7 hours 50 minutes.'
        END
    );
END;
$function$;


-- One authoritative automatic finalizer.
CREATE OR REPLACE FUNCTION public.finalize_attendance_business_rules()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_now_local timestamp := now() AT TIME ZONE 'Asia/Kolkata';
    v_today date := v_now_local::date;
    v_count integer := 0;
    v_rows integer;
BEGIN
    -- 1. Forgotten punch-outs: 10 hours or more => ABSENT and close session.
    WITH expired AS (
        SELECT ps.id
        FROM public.punch_sessions ps
        WHERE ps.punch_out_at IS NULL
          AND ps.punch_in_at <= now() - interval '10 hours'
    ),
    closed AS (
        UPDATE public.punch_sessions ps
        SET
            status = 'auto_absent'::punch_status,
            updated_at = now()
        FROM expired e
        WHERE ps.id = e.id
          AND ps.punch_out_at IS NULL
        RETURNING ps.*
    )
    UPDATE public.attendance a
    SET
        status = 'absent',
        punch_out_time = NULL,
        duty_duration_seconds = 0,
        total_hours = 0,
        earnings = 0,
        updated_at = now()
    FROM closed c
    WHERE a.punch_session_id = c.id;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_count := v_count + v_rows;

    -- 2. Finalize people who never punched in.
    --    Operators use their assigned shift end.
    --    Supervisors use their own assigned shift end.
    --    Anyone without an assigned shift is finalized at local midnight.
    WITH staff AS (
        SELECT
            p.id AS operator_id,
            p.org_id,
            p.role::text AS role,
            COALESCE(
                CASE WHEN p.role::text = 'operator' THEN op_shift.station_id END,
                CASE WHEN p.role::text = 'supervisor' THEN sup_shift.station_id END
            ) AS station_id,
            COALESCE(
                CASE WHEN p.role::text = 'operator' THEN op_shift.shift_id END,
                CASE WHEN p.role::text = 'supervisor' THEN sup_shift.shift_id END
            ) AS shift_id,
            COALESCE(op_shift.duty_end_local, sup_shift.duty_end_local,
                     v_today::timestamp + interval '1 day') AS duty_end_local,
            COALESCE(
                CASE WHEN p.role::text = 'operator' THEN op_shift.is_ot END,
                CASE WHEN p.role::text = 'supervisor' THEN sup_shift.is_ot END,
                false
            ) AS is_ot
        FROM public.profiles p
        LEFT JOIN LATERAL (
            SELECT
                s.id AS shift_id,
                s.station_id,
                COALESCE(sa.is_ot, false) AS is_ot,
                (s.duty_date::timestamp + s.end_time
                    + CASE WHEN s.end_time <= s.start_time THEN interval '1 day' ELSE interval '0 day' END
                ) AS duty_end_local
            FROM public.shift_assignments sa
            JOIN public.shifts s ON s.id = sa.shift_id
            WHERE p.role::text = 'operator'
              AND sa.operator_id = p.id
              AND s.duty_date = v_today
              AND s.is_published = true
            ORDER BY duty_end_local DESC
            LIMIT 1
        ) op_shift ON true
        LEFT JOIN LATERAL (
            SELECT
                s.id AS shift_id,
                s.station_id,
                false AS is_ot,
                (s.duty_date::timestamp + s.end_time
                    + CASE WHEN s.end_time <= s.start_time THEN interval '1 day' ELSE interval '0 day' END
                ) AS duty_end_local
            FROM public.shifts s
            WHERE p.role::text = 'supervisor'
              AND s.supervisor_id = p.id
              AND s.duty_date = v_today
              AND s.is_published = true
            ORDER BY duty_end_local DESC
            LIMIT 1
        ) sup_shift ON true
        WHERE p.is_active = true
          AND p.role::text IN ('operator', 'supervisor')
    ),
    due AS (
        SELECT s.*
        FROM staff s
        WHERE v_now_local >= s.duty_end_local
          AND NOT EXISTS (
              SELECT 1
              FROM public.attendance a
              WHERE a.operator_id = s.operator_id
                AND a.duty_date = v_today
          )
    )
    INSERT INTO public.attendance (
        org_id,
        operator_id,
        station_id,
        shift_id,
        punch_session_id,
        session_id,
        duty_date,
        status,
        is_ot,
        earnings,
        punch_in_time,
        punch_out_time,
        duty_duration_seconds,
        total_hours,
        updated_at
    )
    SELECT
        d.org_id,
        d.operator_id,
        d.station_id,
        d.shift_id,
        NULL,
        NULL,
        v_today,
        'absent',
        d.is_ot,
        0.00,
        NULL,
        NULL,
        0,
        0,
        now()
    FROM due d;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_count := v_count + v_rows;

    RETURN v_count;
END;
$function$;


-- Keep old names safe by delegating to the single finalizer.
CREATE OR REPLACE FUNCTION public.finalize_overdue_punch_sessions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
    RETURN public.finalize_attendance_business_rules();
END;
$function$;

CREATE OR REPLACE FUNCTION public.handle_forgotten_punch_outs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
    PERFORM public.finalize_attendance_business_rules();
END;
$function$;

-- Cron is intentionally NOT created here.
-- Inspect existing cron jobs first so we do not create a duplicate scheduler.
