-- 1. Add instant lookup indexes for all primary query filters
CREATE INDEX IF NOT EXISTS idx_attendance_operator_id ON public.attendance(operator_id);
CREATE INDEX IF NOT EXISTS idx_attendance_duty_date ON public.attendance(duty_date);
CREATE INDEX IF NOT EXISTS idx_attendance_org_id ON public.attendance(org_id);
CREATE INDEX IF NOT EXISTS idx_shift_assignments_op ON public.shift_assignments(operator_id);
CREATE INDEX IF NOT EXISTS idx_shift_assignments_shift ON public.shift_assignments(shift_id);
CREATE INDEX IF NOT EXISTS idx_shifts_station_duty ON public.shifts(station_id, duty_date);
CREATE INDEX IF NOT EXISTS idx_profiles_org_id ON public.profiles(org_id);

-- 2. Fast sub-millisecond operator dashboard RPC
CREATE OR REPLACE FUNCTION public.get_operator_dashboard_overview(
  p_operator_id UUID,
  p_org_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_today_duties JSONB;
  v_upcoming JSONB;
  v_total_duty INT := 0;
  v_total_ot INT := 0;
  v_total_earnings NUMERIC := 0;
  v_week_offs INT := 0;
BEGIN
  -- Today's shifts
  SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb)
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
  ) t;

  -- Upcoming shifts (next 7 days only)
  SELECT COALESCE(jsonb_agg(row_to_json(u)), '[]'::jsonb)
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
      AND s.duty_date <= v_today + INTERVAL '7 days'
    ORDER BY s.duty_date ASC
    LIMIT 10
  ) u;

  -- Quick metrics
  SELECT 
    COUNT(id),
    COALESCE(COUNT(id) FILTER (WHERE status = 'present' OR status = 'completed'), 0)
  INTO v_total_duty, v_total_ot
  FROM public.attendance
  WHERE operator_id = p_operator_id;

  SELECT COALESCE(SUM(s.daily_amount), 0)
  INTO v_total_earnings
  FROM public.attendance a
  JOIN public.shifts s ON s.id = a.shift_id
  WHERE a.operator_id = p_operator_id;

  RETURN jsonb_build_object(
    'today_duties', v_today_duties,
    'upcoming_duties', v_upcoming,
    'total_duty', v_total_duty,
    'total_ot', v_total_ot,
    'total_earnings', v_total_earnings,
    'week_offs', v_week_offs
  );
END;
$$;

NOTIFY pgrst, 'reload schema';