-- 1. Create Notifications Table
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type VARCHAR(50) DEFAULT 'shift_alert', -- 'shift_alert', 'punch_reminder', 'system'
  is_read BOOLEAN DEFAULT FALSE,
  metadata JSONB DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifications_user_policy"
ON public.notifications FOR ALL
TO authenticated, anon
USING (TRUE)
WITH CHECK (TRUE);

-- 2. Automatic Notification Trigger when Shift is Published
CREATE OR REPLACE FUNCTION public.notify_operators_on_shift_publish()
RETURNS TRIGGER AS $$
DECLARE
  v_assignment RECORD;
  v_station_name TEXT;
BEGIN
  SELECT name INTO v_station_name FROM public.stations WHERE id = NEW.station_id;

  FOR v_assignment IN 
    SELECT sa.operator_id, os.system_name, sa.is_ot
    FROM public.shift_assignments sa
    LEFT JOIN public.station_operating_systems os ON sa.operating_system_id = os.id
    WHERE sa.shift_id = NEW.id
  LOOP
    INSERT INTO public.notifications (
      org_id,
      user_id,
      title,
      body,
      type,
      metadata
    ) VALUES (
      NEW.org_id,
      v_assignment.operator_id,
      CASE WHEN v_assignment.is_ot THEN 'New OT Shift Assigned!' ELSE 'New Shift Published' END,
      'Duty at ' || v_station_name || ' (' || NEW.shift_name || ') on ' || NEW.duty_date || ' [' || NEW.start_time || ' - ' || NEW.end_time || ']',
      'shift_alert',
      jsonb_build_object(
        'shift_id', NEW.id,
        'station_id', NEW.station_id,
        'is_ot', v_assignment.is_ot
      )
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_operators_on_shift_publish ON public.shifts;
CREATE TRIGGER trg_notify_operators_on_shift_publish
AFTER INSERT OR UPDATE OF is_published ON public.shifts
FOR EACH ROW
WHEN (NEW.is_published = TRUE)
EXECUTE FUNCTION public.notify_operators_on_shift_publish();


-- 1. Add fcm_token column to profiles table
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- 2. Optional: Index for fast lookup by token
CREATE INDEX IF NOT EXISTS idx_profiles_fcm_token ON public.profiles(fcm_token);


-- 1. Ensure profiles table has the fcm_token column for device tokens
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- 2. Create the notifications history table
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type VARCHAR(50) DEFAULT 'shift_alert',
  is_read BOOLEAN DEFAULT FALSE,
  metadata JSONB DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Enable Row Level Security
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- 4. Allow read/write access to authenticated users
CREATE POLICY "notifications_authenticated_access"
ON public.notifications FOR ALL
TO authenticated, anon
USING (TRUE)
WITH CHECK (TRUE);

-- 5. Enable Realtime on notifications table
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;


-- 1. Ensure extensions and schema exist
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE SCHEMA IF NOT EXISTS supabase_functions;

-- 2. Define the missing http_request() webhook dispatcher function
CREATE OR REPLACE FUNCTION supabase_functions.http_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
DECLARE
  request_id BIGINT;
  payload JSONB;
  url TEXT := TG_ARGV[0];
  method TEXT := TG_ARGV[1];
  headers JSONB := COALESCE(TG_ARGV[2]::JSONB, '{}'::JSONB);
  params JSONB := COALESCE(TG_ARGV[3]::JSONB, '{}'::JSONB);
  timeout_ms INTEGER := COALESCE(TG_ARGV[4]::INTEGER, 5000);
BEGIN
  IF TG_OP = 'DELETE' THEN
    payload = jsonb_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', null,
      'old_record', row_to_json(OLD)
    );
  ELSIF TG_OP = 'UPDATE' THEN
    payload = jsonb_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', row_to_json(NEW),
      'old_record', row_to_json(OLD)
    );
  ELSE
    payload = jsonb_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', row_to_json(NEW),
      'old_record', null
    );
  END IF;

  -- Dispatch outgoing async HTTP POST to Edge Function
  SELECT net.http_post(
    url := url,
    headers := headers,
    body := payload,
    timeout_milliseconds := timeout_ms
  ) INTO request_id;

  RETURN NULL;
END;
$$;

-- 3. Grant necessary execution rights
GRANT USAGE ON SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;


-- Add missing columns to the existing notifications table
ALTER TABLE public.notifications 
ADD COLUMN IF NOT EXISTS type VARCHAR(50) DEFAULT 'shift_alert',
ADD COLUMN IF NOT EXISTS is_read BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::JSONB;


CREATE OR REPLACE FUNCTION public.handle_new_shift_assignment_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_shift_name TEXT;
  v_start_time TIME;
  v_end_time TIME;
  v_duty_date DATE;
  v_station_name TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  -- Fetch Shift & Station details
  SELECT s.shift_name, s.start_time, s.end_time, s.duty_date, st.name
  INTO v_shift_name, v_start_time, v_end_time, v_duty_date, v_station_name
  FROM public.shifts s
  LEFT JOIN public.stations st ON st.id = s.station_id
  WHERE s.id = NEW.shift_id;

  IF NEW.is_ot THEN
    v_title := '⭐ Overtime (OT) Duty Assigned';
  ELSE
    v_title := '📋 New Shift Assigned';
  END IF;

  v_body := format('%s at %s on %s (%s - %s)', 
    v_shift_name, 
    COALESCE(v_station_name, 'Metro Station'), 
    v_duty_date, 
    v_start_time, 
    v_end_time
  );

  -- Insert notification record (which triggers the FCM Webhook)
  INSERT INTO public.notifications (org_id, user_id, title, body, type, metadata)
  VALUES (
    NEW.org_id,
    NEW.operator_id,
    v_title,
    v_body,
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