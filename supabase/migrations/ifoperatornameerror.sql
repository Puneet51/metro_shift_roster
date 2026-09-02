CREATE OR REPLACE FUNCTION public.handle_new_shift_assignment_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_shift_name TEXT;
  v_duty_date DATE;
  v_station_name TEXT;
  v_operator_id UUID;
  v_org_id UUID;
BEGIN
  -- Use NEW.operator_id directly
  v_operator_id := NEW.operator_id;
  v_org_id := NEW.org_id;

  -- Fetch Shift Details
  SELECT s.shift_name, s.duty_date, st.name
  INTO v_shift_name, v_duty_date, v_station_name
  FROM public.shifts s
  LEFT JOIN public.stations st ON st.id = s.station_id
  WHERE s.id = NEW.shift_id;

  -- Insert notification record
  INSERT INTO public.notifications (
    org_id, 
    user_id, 
    title, 
    body, 
    type, 
    metadata
  )
  VALUES (
    COALESCE(v_org_id, '00000000-0000-0000-0000-000000000001'::UUID),
    v_operator_id,
    CASE WHEN COALESCE(NEW.is_ot, FALSE) THEN '⭐ Overtime Shift Assigned' ELSE '📋 New Shift Assigned' END,
    format('%s at %s on %s', COALESCE(v_shift_name, 'Shift'), COALESCE(v_station_name, 'Station'), COALESCE(v_duty_date::TEXT, 'Upcoming Date')),
    'shift_assignment',
    jsonb_build_object('shift_id', NEW.shift_id, 'assignment_id', NEW.id)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_shift_assignment_push ON public.shift_assignments;

CREATE TRIGGER trigger_shift_assignment_push
AFTER INSERT ON public.shift_assignments
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_shift_assignment_notification();

NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';


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
  v_total_duty INT;
  v_total_ot INT;
  v_total_earnings NUMERIC;
  v_week_offs INT;
BEGIN
  -- 1. Fetch ALL duties assigned to this operator for today
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

  -- 2. Fetch upcoming future shifts
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

  -- 3. Counts & stats
  SELECT COUNT(*) INTO v_total_duty
  FROM public.shift_assignments sa
  JOIN public.shifts s ON s.id = sa.shift_id
  WHERE sa.operator_id = p_operator_id AND s.duty_date <= v_today;

  SELECT COUNT(*) INTO v_total_ot
  FROM public.shift_assignments
  WHERE operator_id = p_operator_id AND is_ot = true;

  SELECT COALESCE(SUM(s.daily_amount), 0) INTO v_total_earnings
  FROM public.shift_assignments sa
  JOIN public.shifts s ON s.id = sa.shift_id
  WHERE sa.operator_id = p_operator_id AND s.duty_date <= v_today;

  SELECT COUNT(*) INTO v_week_offs
  FROM public.week_off_leaves
  WHERE user_id = p_operator_id AND status = 'approved';

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