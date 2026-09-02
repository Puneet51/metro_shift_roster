CREATE OR REPLACE FUNCTION public.get_operator_dashboard_overview(
  p_operator_id UUID,
  p_org_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_today_duties JSONB;
  v_upcoming JSONB;
  v_completed_duty INT := 0;
  v_total_ot INT := 0;
  v_total_earnings NUMERIC := 0;
  v_week_offs INT := 0;
BEGIN
  -- 1. Today's Assigned Duties
  SELECT COALESCE(jsonb_agg(d), '[]'::jsonb)
  INTO v_today_duties
  FROM (
    SELECT 
      s.id AS shift_id,
      s.shift_name,
      s.duty_date,
      s.start_time,
      s.end_time,
      st.name AS station_name,
      sos.system_name,
      sa.is_ot
    FROM public.shift_assignments sa
    JOIN public.shifts s ON s.id = sa.shift_id
    LEFT JOIN public.stations st ON st.id = s.station_id
    LEFT JOIN public.station_operating_systems sos ON sos.id = sa.operating_system_id
    WHERE sa.operator_id = p_operator_id
      AND s.duty_date = v_today
    ORDER BY s.start_time ASC
  ) d;

  -- 2. Upcoming Duties
  SELECT COALESCE(jsonb_agg(u), '[]'::jsonb)
  INTO v_upcoming
  FROM (
    SELECT 
      s.id AS shift_id,
      s.shift_name,
      s.duty_date,
      s.start_time,
      s.end_time,
      st.name AS station_name,
      sos.system_name,
      sa.is_ot
    FROM public.shift_assignments sa
    JOIN public.shifts s ON s.id = sa.shift_id
    LEFT JOIN public.stations st ON st.id = s.station_id
    LEFT JOIN public.station_operating_systems sos ON sos.id = sa.operating_system_id
    WHERE sa.operator_id = p_operator_id
      AND s.duty_date > v_today
    ORDER BY s.duty_date ASC, s.start_time ASC
    LIMIT 10
  ) u;

  -- 3. Completed Duties: ONLY when Punch IN and Punch OUT are both recorded
  SELECT COUNT(a.id)
  INTO v_completed_duty
  FROM public.attendance a
  WHERE a.operator_id = p_operator_id
    AND a.punch_in_time IS NOT NULL
    AND a.punch_out_time IS NOT NULL;

  -- 4. Total Overtime (OT): Only completed OT duties
  SELECT COUNT(a.id)
  INTO v_total_ot
  FROM public.attendance a
  JOIN public.shift_assignments sa ON sa.id = a.assignment_id
  WHERE a.operator_id = p_operator_id
    AND a.punch_in_time IS NOT NULL
    AND a.punch_out_time IS NOT NULL
    AND sa.is_ot = true;

  -- 5. Total Earnings: Sum daily amount of completed shifts
  SELECT COALESCE(SUM(s.daily_amount), 0)
  INTO v_total_earnings
  FROM public.attendance a
  JOIN public.shifts s ON s.id = a.shift_id
  WHERE a.operator_id = p_operator_id
    AND a.punch_in_time IS NOT NULL
    AND a.punch_out_time IS NOT NULL;

  -- 6. Week Offs Check
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'week_off_leaves') THEN
    EXECUTE 'SELECT COUNT(*) FROM public.week_off_leaves WHERE user_id = $1 AND status = ''approved'''
    INTO v_week_offs
    USING p_operator_id;
  END IF;

  RETURN jsonb_build_object(
    'today_duties', v_today_duties,
    'upcoming_duties', v_upcoming,
    'total_duty', v_completed_duty,
    'total_ot', v_total_ot,
    'total_earnings', v_total_earnings,
    'week_offs', v_week_offs
  );
END;
$$;

NOTIFY pgrst, 'reload schema';

ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS emp_code TEXT,
ADD COLUMN IF NOT EXISTS biometric_id TEXT,
ADD COLUMN IF NOT EXISTS father_name TEXT,
ADD COLUMN IF NOT EXISTS doj DATE,
ADD COLUMN IF NOT EXISTS esi_no TEXT,
ADD COLUMN IF NOT EXISTS uan_no TEXT;

NOTIFY pgrst, 'reload schema';