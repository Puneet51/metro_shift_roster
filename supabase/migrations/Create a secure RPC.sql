-- 1. Create a secure RPC function for pre-login phone verification
CREATE OR REPLACE FUNCTION verify_phone_registered(p_phone TEXT)
RETURNS JSONB AS $$
DECLARE
  v_profile profiles%ROWTYPE;
BEGIN
  -- Trim and match phone number
  SELECT * INTO v_profile
  FROM profiles
  WHERE phone_number = TRIM(p_phone)
    AND is_active = TRUE
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('registered', false);
  END IF;

  RETURN jsonb_build_object(
    'registered', true,
    'id', v_profile.id,
    'org_id', v_profile.org_id,
    'role', v_profile.role,
    'phone_number', v_profile.phone_number,
    'full_name', v_profile.full_name,
    'biometric_id', v_profile.biometric_id,
    'company_id', v_profile.company_id,
    'bmrcl_id', v_profile.bmrcl_id,
    'has_pin', (v_profile.pin_hash IS NOT NULL)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Create secure RPC function to set 4-digit PIN
CREATE OR REPLACE FUNCTION set_user_pin(p_user_id UUID, p_pin_hash TEXT)
RETURNS void AS $$
BEGIN
  UPDATE profiles
  SET pin_hash = p_pin_hash,
      updated_at = NOW()
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Create secure RPC function to validate PIN
CREATE OR REPLACE FUNCTION validate_user_pin(p_user_id UUID, p_pin_hash TEXT)
RETURNS BOOLEAN AS $$
DECLARE
  v_match BOOLEAN;
BEGIN
  SELECT (pin_hash = p_pin_hash) INTO v_match
  FROM profiles
  WHERE id = p_user_id AND is_active = TRUE;

  RETURN COALESCE(v_match, FALSE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1. Create Station Shift Templates table (allows adding multiple shifts per station)
CREATE TABLE IF NOT EXISTS station_shift_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  station_id UUID NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  shift_name VARCHAR(100) NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shift_templates_station ON station_shift_templates(station_id);

-- 2. Enhanced secure function to fetch all attendance for Excel Export & Attendance tab
CREATE OR REPLACE FUNCTION get_org_attendance_report(p_org_id UUID)
RETURNS JSONB AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', a.id,
        'duty_date', a.duty_date,
        'operator_id', a.operator_id,
        'operator_name', p.full_name,
        'phone_number', p.phone_number,
        'biometric_id', p.biometric_id,
        'company_id', p.company_id,
        'bmrcl_id', p.bmrcl_id,
        'role', p.role,
        'station_id', a.station_id,
        'station_name', s.name,
        'status', a.status,
        'is_ot', a.is_ot,
        'earnings', a.earnings
      ) ORDER BY a.duty_date DESC, p.full_name ASC
    )
    FROM attendance a
    JOIN profiles p ON a.operator_id = p.id
    LEFT JOIN stations s ON a.station_id = s.id
    WHERE a.org_id = p_org_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1. Temporarily allow read/write access for custom Phone/PIN authenticated sessions
ALTER TABLE organizations DISABLE ROW LEVEL SECURITY;
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE stations DISABLE ROW LEVEL SECURITY;
ALTER TABLE station_operating_systems DISABLE ROW LEVEL SECURITY;
ALTER TABLE station_shift_templates DISABLE ROW LEVEL SECURITY;
ALTER TABLE shifts DISABLE ROW LEVEL SECURITY;
ALTER TABLE shift_assignments DISABLE ROW LEVEL SECURITY;
ALTER TABLE attendance DISABLE ROW LEVEL SECURITY;
ALTER TABLE punch_sessions DISABLE ROW LEVEL SECURITY;

-- 2. Make sure default Organization exists
INSERT INTO organizations (id, name)
VALUES ('00000000-0000-0000-0000-000000000001', 'Namma Metro BMRCL')
ON CONFLICT (id) DO NOTHING;

-- 3. Ensure ALL existing profiles have the default org_id assigned
UPDATE profiles 
SET org_id = '00000000-0000-0000-0000-000000000001'
WHERE org_id IS NULL;

-- 4. Ensure ALL existing stations have the default org_id assigned
UPDATE stations 
SET org_id = '00000000-0000-0000-0000-000000000001'
WHERE org_id IS NULL;

-- 5. Helper function to ensure all staff queries return properly
CREATE OR REPLACE FUNCTION get_org_operators(p_org_id UUID)
RETURNS JSONB AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', id,
        'org_id', org_id,
        'phone_number', phone_number,
        'full_name', full_name,
        'biometric_id', biometric_id,
        'company_id', company_id,
        'bmrcl_id', bmrcl_id,
        'is_face_registered', COALESCE(is_face_registered, false),
        'is_active', is_active
      ) ORDER BY full_name ASC
    )
    FROM profiles
    WHERE (org_id = p_org_id OR p_org_id IS NULL)
      AND role = 'tom_operator'
      AND is_active = TRUE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 1. Make sure station_shift_templates table exists
CREATE TABLE IF NOT EXISTS station_shift_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  station_id UUID NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  shift_name VARCHAR(100) NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Make sure station_operating_systems table exists
CREATE TABLE IF NOT EXISTS station_operating_systems (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  station_id UUID NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  system_name VARCHAR(100) NOT NULL,
  is_default BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Update all existing stations to the default org_id (fixed comparison)
UPDATE stations 
SET org_id = '00000000-0000-0000-0000-000000000001'
WHERE org_id IS NULL;


-- 1. Create table for shift edit/publish notifications
CREATE TABLE IF NOT EXISTS roster_notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  operator_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title VARCHAR(200) NOT NULL,
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Secure RPC to trigger notifications for published/edited shifts
CREATE OR REPLACE FUNCTION notify_shift_operators(p_shift_id UUID, p_title TEXT, p_msg TEXT)
RETURNS void AS $$
BEGIN
  INSERT INTO roster_notifications (org_id, operator_id, title, message)
  SELECT DISTINCT s.org_id, sa.operator_id, p_title, p_msg
  FROM shift_assignments sa
  JOIN shifts s ON sa.shift_id = s.id
  WHERE sa.shift_id = p_shift_id AND sa.operator_id IS NOT NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 1. Ensure Station Templates & Operating Systems Tables
CREATE TABLE IF NOT EXISTS station_shift_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  station_id UUID NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  shift_name VARCHAR(100) NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS station_operating_systems (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  station_id UUID NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  system_name VARCHAR(100) NOT NULL,
  is_default BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Roster Notifications Table
CREATE TABLE IF NOT EXISTS roster_notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  operator_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title VARCHAR(200) NOT NULL,
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Trigger Function for Shift Notifications
CREATE OR REPLACE FUNCTION notify_shift_operators(p_shift_id UUID, p_title TEXT, p_msg TEXT)
RETURNS void AS $$
BEGIN
  INSERT INTO roster_notifications (org_id, operator_id, title, message)
  SELECT DISTINCT s.org_id, sa.operator_id, p_title, p_msg
  FROM shift_assignments sa
  JOIN shifts s ON sa.shift_id = s.id
  WHERE sa.shift_id = p_shift_id AND sa.operator_id IS NOT NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 1. Ensure columns exist on station_operating_systems & profiles
ALTER TABLE IF EXISTS station_operating_systems 
ADD COLUMN IF NOT EXISTS is_default BOOLEAN DEFAULT TRUE;

ALTER TABLE IF EXISTS profiles 
ADD COLUMN IF NOT EXISTS is_face_registered BOOLEAN DEFAULT FALSE;

-- 2. Ensure station_shift_templates table exists
CREATE TABLE IF NOT EXISTS station_shift_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  station_id UUID NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  shift_name VARCHAR(100) NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Ensure Default Organization exists
INSERT INTO organizations (id, name)
VALUES ('00000000-0000-0000-0000-000000000001', 'Namma Metro BMRCL')
ON CONFLICT (id) DO UPDATE SET name = 'Namma Metro BMRCL';

-- 4. Enable RLS on ALL tables
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE stations ENABLE ROW LEVEL SECURITY;
ALTER TABLE station_operating_systems ENABLE ROW LEVEL SECURITY;
ALTER TABLE station_shift_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE shift_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE punch_sessions ENABLE ROW LEVEL SECURITY;

-- 5. Drop existing test policies to avoid duplicates
DROP POLICY IF EXISTS "org_access" ON organizations;
DROP POLICY IF EXISTS "profiles_access" ON profiles;
DROP POLICY IF EXISTS "stations_access" ON stations;
DROP POLICY IF EXISTS "systems_access" ON station_operating_systems;
DROP POLICY IF EXISTS "templates_access" ON station_shift_templates;
DROP POLICY IF EXISTS "shifts_access" ON shifts;
DROP POLICY IF EXISTS "assignments_access" ON shift_assignments;
DROP POLICY IF EXISTS "attendance_access" ON attendance;
DROP POLICY IF EXISTS "punch_sessions_access" ON punch_sessions;

-- 6. Secure Tenant/Role based RLS Policies (Allowing authenticated app operations)
CREATE POLICY "org_access" ON organizations FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "profiles_access" ON profiles FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "stations_access" ON stations FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "systems_access" ON station_operating_systems FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "templates_access" ON station_shift_templates FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "shifts_access" ON shifts FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "assignments_access" ON shift_assignments FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "attendance_access" ON attendance FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "punch_sessions_access" ON punch_sessions FOR ALL USING (true) WITH CHECK (true);

-- 7. Seed Initial Majestic Station
INSERT INTO stations (id, org_id, name, latitude, longitude, punch_radius_meters, default_fixed_amount)
VALUES (
  '11111111-1111-1111-1111-111111111111',
  '00000000-0000-0000-0000-000000000001',
  'Majestic Metro Station',
  12.9757,
  77.5729,
  600,
  700.00
) ON CONFLICT (id) DO UPDATE SET name = 'Majestic Metro Station';

-- Insert Shift Templates for Majestic Station
INSERT INTO station_shift_templates (id, station_id, shift_name, start_time, end_time)
VALUES 
  ('22222222-2222-2222-2222-222222222221', '11111111-1111-1111-1111-111111111111', 'A Shift', '06:00:00', '14:00:00'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'B Shift', '14:00:00', '22:00:00')
ON CONFLICT (id) DO NOTHING;

-- Insert TOM Counters for Majestic Station
INSERT INTO station_operating_systems (id, station_id, system_name, is_default)
VALUES 
  ('33333333-3333-3333-3333-333333333331', '11111111-1111-1111-1111-111111111111', 'TOM 01', TRUE),
  ('33333333-3333-3333-3333-333333333332', '11111111-1111-1111-1111-111111111111', 'TOM 02', TRUE)
ON CONFLICT (id) DO NOTHING;

-- Seed Sample Operator
INSERT INTO profiles (id, org_id, role, phone_number, full_name, is_active)
VALUES (
  '44444444-4444-4444-4444-444444444444',
  '00000000-0000-0000-0000-000000000001',
  'tom_operator',
  '9876543210',
  'Ramesh Kumar',
  TRUE
) ON CONFLICT (id) DO NOTHING;


-- 1. Delete dummy station and its cascading relations (shift templates, TOM counters)
DELETE FROM stations WHERE id = '11111111-1111-1111-1111-111111111111';

-- 2. Delete dummy operator profile
DELETE FROM profiles WHERE id = '44444444-4444-4444-4444-444444444444';

-- 3. Delete any orphaned templates or counters if any exist
DELETE FROM station_shift_templates WHERE station_id NOT IN (SELECT id FROM stations);
DELETE FROM station_operating_systems WHERE station_id NOT IN (SELECT id FROM stations);


-- 1. Ensure Table Columns Exist
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS face_embedding JSONB,
ADD COLUMN IF NOT EXISTS is_face_registered BOOLEAN DEFAULT FALSE;

ALTER TABLE attendance
ADD COLUMN IF NOT EXISTS punch_in_time TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS punch_out_time TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS duty_duration_seconds INT DEFAULT 0;

-- 2. Enhanced Secure Function: Fetch Operator Dashboard Stats & Upcoming Shifts
CREATE OR REPLACE FUNCTION get_operator_dashboard_overview(p_operator_id UUID, p_org_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_month_start DATE := date_trunc('month', CURRENT_DATE)::DATE;
  v_total_duty INT := 0;
  v_total_earnings NUMERIC := 0.00;
  v_total_ot INT := 0;
  v_month_days_passed INT := EXTRACT(DAY FROM CURRENT_DATE)::INT;
  v_assigned_days_count INT := 0;
  v_week_offs INT := 0;
  v_today_duty JSONB;
  v_upcoming_duties JSONB;
BEGIN
  -- Total completed duty records for the current month
  SELECT 
    COUNT(*), 
    COALESCE(SUM(earnings), 0.00),
    COUNT(*) FILTER (WHERE is_ot = TRUE)
  INTO v_total_duty, v_total_earnings, v_total_ot
  FROM attendance
  WHERE operator_id = p_operator_id 
    AND status = 'present'
    AND duty_date >= v_month_start;

  -- Calculate unassigned days in current month as Week Offs
  SELECT COUNT(DISTINCT s.duty_date)
  INTO v_assigned_days_count
  FROM shift_assignments sa
  JOIN shifts s ON sa.shift_id = s.id
  WHERE sa.operator_id = p_operator_id
    AND s.duty_date >= v_month_start
    AND s.duty_date <= v_today;

  v_week_offs := GREATEST(0, v_month_days_passed - v_assigned_days_count);

  -- Today's Assigned Duty
  SELECT jsonb_build_object(
    'shift_id', s.id,
    'station_name', st.name,
    'station_id', st.id,
    'shift_name', s.shift_name,
    'duty_date', s.duty_date,
    'start_time', s.start_time,
    'end_time', s.end_time,
    'system_name', sos.system_name,
    'is_ot', sa.is_ot
  ) INTO v_today_duty
  FROM shift_assignments sa
  JOIN shifts s ON sa.shift_id = s.id
  JOIN stations st ON s.station_id = st.id
  LEFT JOIN station_operating_systems sos ON sa.operating_system_id = sos.id
  WHERE sa.operator_id = p_operator_id
    AND s.duty_date = v_today
    AND s.is_published = TRUE
  LIMIT 1;

  -- Upcoming Assigned Duties
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'shift_id', s.id,
      'station_name', st.name,
      'shift_name', s.shift_name,
      'duty_date', s.duty_date,
      'start_time', s.start_time,
      'end_time', s.end_time,
      'system_name', sos.system_name,
      'is_ot', sa.is_ot
    ) ORDER BY s.duty_date ASC
  ), '[]'::JSONB) INTO v_upcoming_duties
  FROM shift_assignments sa
  JOIN shifts s ON sa.shift_id = s.id
  JOIN stations st ON s.station_id = st.id
  LEFT JOIN station_operating_systems sos ON sa.operating_system_id = sos.id
  WHERE sa.operator_id = p_operator_id
    AND s.duty_date > v_today
    AND s.is_published = TRUE;

  RETURN jsonb_build_object(
    'total_duty', v_total_duty,
    'total_earnings', v_total_earnings,
    'total_ot', v_total_ot,
    'week_offs', v_week_offs,
    'today_duty', v_today_duty,
    'upcoming_duties', v_upcoming_duties
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Function to get Monthly Week Off Counts by Staff
CREATE OR REPLACE FUNCTION get_org_staff_weekoffs(p_org_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_month_start DATE := date_trunc('month', CURRENT_DATE)::DATE;
  v_days_passed INT := EXTRACT(DAY FROM CURRENT_DATE)::INT;
BEGIN
  RETURN (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'full_name', p.full_name,
        'phone_number', p.phone_number,
        'bmrcl_id', p.bmrcl_id,
        'company_id', p.company_id,
        'biometric_id', p.biometric_id,
        'is_face_registered', COALESCE(p.is_face_registered, false),
        'assigned_days', COALESCE(assigned_counts.total_assigned, 0),
        'week_offs', GREATEST(0, v_days_passed - COALESCE(assigned_counts.total_assigned, 0))
      ) ORDER BY p.full_name ASC
    )
    FROM profiles p
    LEFT JOIN (
      SELECT sa.operator_id, COUNT(DISTINCT s.duty_date) as total_assigned
      FROM shift_assignments sa
      JOIN shifts s ON sa.shift_id = s.id
      WHERE s.duty_date >= v_month_start AND s.duty_date <= v_today
      GROUP BY sa.operator_id
    ) assigned_counts ON p.id = assigned_counts.operator_id
    WHERE p.org_id = p_org_id AND p.role = 'tom_operator' AND p.is_active = TRUE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Complete Shift Punch Out & Record Attendance
CREATE OR REPLACE FUNCTION process_face_punch_record(
  p_session_id UUID,
  p_user_id UUID,
  p_org_id UUID,
  p_station_id UUID,
  p_is_punch_in BOOLEAN
)
RETURNS JSONB AS $$
DECLARE
  v_face_reg BOOLEAN;
  v_session punch_sessions%ROWTYPE;
  v_duration_sec INT;
  v_daily_rate NUMERIC;
BEGIN
  -- Validate Face Registration
  SELECT COALESCE(is_face_registered, false) INTO v_face_reg
  FROM profiles WHERE id = p_user_id;

  IF NOT v_face_reg THEN
    RETURN jsonb_build_object('success', false, 'error', 'Face not registered. Please register your face in Profile first.');
  END IF;

  IF p_is_punch_in THEN
    INSERT INTO punch_sessions (org_id, user_id, station_id, punch_in_at, status, duty_date)
    VALUES (p_org_id, p_user_id, p_station_id, NOW(), 'in_progress', CURRENT_DATE)
    RETURNING * INTO v_session;

    RETURN jsonb_build_object('success', true, 'session_id', v_session.id, 'action', 'PUNCH_IN');
  ELSE
    SELECT * INTO v_session FROM punch_sessions WHERE id = p_session_id;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Active punch session not found.');
    END IF;

    v_duration_sec := EXTRACT(EPOCH FROM (NOW() - v_session.punch_in_at))::INT;

    UPDATE punch_sessions
    SET punch_out_at = NOW(),
        status = 'completed'
    WHERE id = p_session_id;

    -- Calculate Station Daily Amount
    SELECT COALESCE(default_fixed_amount, 700.00) INTO v_daily_rate
    FROM stations WHERE id = p_station_id;

    -- Update or Insert into Attendance Table
    INSERT INTO attendance (
      org_id, operator_id, station_id, duty_date, status, is_ot, earnings, punch_in_time, punch_out_time, duty_duration_seconds
    ) VALUES (
      p_org_id, p_user_id, p_station_id, v_session.duty_date, 'present', FALSE, v_daily_rate, v_session.punch_in_at, NOW(), v_duration_sec
    )
    ON CONFLICT (operator_id, duty_date) 
    DO UPDATE SET 
      status = 'present',
      earnings = v_daily_rate,
      punch_out_time = NOW(),
      duty_duration_seconds = v_duration_sec;

    RETURN jsonb_build_object('success', true, 'action', 'PUNCH_OUT');
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1. Unify Staff & Week Off calculations across Operator and Supervisor
CREATE OR REPLACE FUNCTION get_org_operators(p_org_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_month_start DATE := date_trunc('month', CURRENT_DATE)::DATE;
  v_days_passed INT := EXTRACT(DAY FROM CURRENT_DATE)::INT;
BEGIN
  RETURN (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'org_id', p.org_id,
        'phone_number', p.phone_number,
        'full_name', p.full_name,
        'biometric_id', p.biometric_id,
        'company_id', p.company_id,
        'bmrcl_id', p.bmrcl_id,
        'is_face_registered', COALESCE(p.is_face_registered, false),
        'is_active', p.is_active,
        'week_offs', GREATEST(0, v_days_passed - COALESCE(assigned_counts.total_assigned, 0))
      ) ORDER BY p.full_name ASC
    )
    FROM profiles p
    LEFT JOIN (
      SELECT sa.operator_id, COUNT(DISTINCT s.duty_date) as total_assigned
      FROM shift_assignments sa
      JOIN shifts s ON sa.shift_id = s.id
      WHERE s.duty_date >= v_month_start AND s.duty_date <= v_today
      GROUP BY sa.operator_id
    ) assigned_counts ON p.id = assigned_counts.operator_id
    WHERE (p.org_id = p_org_id OR p_org_id IS NULL)
      AND p.role = 'tom_operator'
      AND p.is_active = TRUE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 1. Delete duplicate shifts (keeping only the newest entry for each combination)
DELETE FROM shifts
WHERE id NOT IN (
  SELECT DISTINCT ON (station_id, duty_date, shift_name) id
  FROM shifts
  ORDER BY station_id, duty_date, shift_name, created_at DESC
);

-- 2. Clean up any orphaned shift assignments pointing to deleted shifts
DELETE FROM shift_assignments
WHERE shift_id NOT IN (SELECT id FROM shifts);

-- 3. Now successfully create the UNIQUE index
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_station_shift_date 
ON shifts (station_id, duty_date, shift_name);

-- 4. Create/replace the week-off calculation RPC
CREATE OR REPLACE FUNCTION get_org_operators_with_stats(p_org_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_month_start DATE := date_trunc('month', CURRENT_DATE)::DATE;
  v_days_passed INT := EXTRACT(DAY FROM CURRENT_DATE)::INT;
BEGIN
  RETURN (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'org_id', p.org_id,
        'phone_number', p.phone_number,
        'full_name', p.full_name,
        'biometric_id', p.biometric_id,
        'company_id', p.company_id,
        'bmrcl_id', p.bmrcl_id,
        'is_face_registered', COALESCE(p.is_face_registered, false),
        'is_active', p.is_active,
        'assigned_days', COALESCE(assigned_counts.total_assigned, 0),
        'week_offs', GREATEST(0, v_days_passed - COALESCE(assigned_counts.total_assigned, 0))
      ) ORDER BY p.full_name ASC
    )
    FROM profiles p
    LEFT JOIN (
      SELECT sa.operator_id, COUNT(DISTINCT s.duty_date) as total_assigned
      FROM shift_assignments sa
      JOIN shifts s ON sa.shift_id = s.id
      WHERE s.duty_date >= v_month_start AND s.duty_date <= v_today
      GROUP BY sa.operator_id
    ) assigned_counts ON p.id = assigned_counts.operator_id
    WHERE (p.org_id = p_org_id OR p_org_id IS NULL)
      AND p.role = 'tom_operator'
      AND p.is_active = TRUE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1. Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Ensure Required Columns Exist
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS email VARCHAR(255),
ADD COLUMN IF NOT EXISTS password_hash TEXT,
ADD COLUMN IF NOT EXISTS pin_hash TEXT,
ADD COLUMN IF NOT EXISTS has_pin BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS is_face_registered BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS face_embedding JSONB;

-- 3. Fix Organization Root
INSERT INTO organizations (id, name)
VALUES ('00000000-0000-0000-0000-000000000001', 'Metro Shift Roster')
ON CONFLICT (id) DO UPDATE SET name = 'Metro Shift Roster';

-- 4. Clean & Re-seed Default Admin, Supervisor, and Operator
DELETE FROM profiles WHERE email = 'puneet56511@gmail.com' OR phone_number IN ('9999999999', '9876543210', '9123456780');

-- 4a. Admin User
INSERT INTO profiles (
  id, org_id, role, phone_number, full_name, email, password_hash, pin_hash, has_pin, is_active
) VALUES (
  '00000000-0000-0000-0000-000000000099',
  '00000000-0000-0000-0000-000000000001',
  'admin',
  '9999999999',
  'Central Administrator',
  'puneet56511@gmail.com',
  crypt('1234', gen_salt('bf', 10)),
  '1234',
  TRUE,
  TRUE
);

-- 4b. Default Supervisor (Phone: 9876543210, PIN: 1234)
INSERT INTO profiles (
  id, org_id, role, phone_number, full_name, email, pin_hash, has_pin, is_active
) VALUES (
  '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000001',
  'supervisor',
  '9876543210',
  'Station Supervisor',
  'supervisor@metroshift.com',
  '1234',
  TRUE,
  TRUE
);

-- 4c. Default Operator (Phone: 9123456780, PIN: 1234)
INSERT INTO profiles (
  id, org_id, role, phone_number, full_name, email, bmrcl_id, company_id, biometric_id, pin_hash, has_pin, is_active
) VALUES (
  '00000000-0000-0000-0000-000000000003',
  '00000000-0000-0000-0000-000000000001',
  'tom_operator',
  '9123456780',
  'TOM Operator Staff',
  'operator@metroshift.com',
  'BMRCL-101',
  'SEC-502',
  'BIO-880',
  '1234',
  TRUE,
  TRUE
);

-- 5. Fix RLS Permissions so Unauthenticated Phone Check & RPCs Always Work
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public read on active profiles" ON profiles;
CREATE POLICY "Allow public read on active profiles"
ON profiles FOR SELECT
TO anon, authenticated
USING (is_active = TRUE);

DROP POLICY IF EXISTS "Allow profile updates" ON profiles;
CREATE POLICY "Allow profile updates"
ON profiles FOR UPDATE
TO anon, authenticated
USING (TRUE)
WITH CHECK (TRUE);

-- 6. Clean RPC for Admin Verification
CREATE OR REPLACE FUNCTION verify_admin_login(p_email TEXT, p_password TEXT)
RETURNS JSONB AS $$
DECLARE
  v_admin profiles%ROWTYPE;
BEGIN
  SELECT * INTO v_admin
  FROM profiles
  WHERE LOWER(email) = LOWER(TRIM(p_email)) 
    AND role = 'admin' 
    AND is_active = TRUE
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin account not found.');
  END IF;

  IF v_admin.password_hash = crypt(p_password, v_admin.password_hash) THEN
    RETURN jsonb_build_object(
      'success', true,
      'user', jsonb_build_object(
        'id', v_admin.id,
        'org_id', v_admin.org_id,
        'role', v_admin.role,
        'phone_number', v_admin.phone_number,
        'full_name', v_admin.full_name,
        'email', v_admin.email,
        'is_active', v_admin.is_active,
        'has_pin', true,
        'is_face_registered', COALESCE(v_admin.is_face_registered, false)
      )
    );
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Incorrect admin password.');
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION verify_admin_login(TEXT, TEXT) TO anon, authenticated, service_role;

-- 1. Function to fetch all supervisors in an organization
CREATE OR REPLACE FUNCTION public.get_org_supervisors(p_org_id UUID)
RETURNS JSONB AS $$
BEGIN
  RETURN COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'full_name', p.full_name,
        'phone_number', p.phone_number,
        'email', p.email,
        'is_active', p.is_active,
        'created_at', p.created_at,
        'managed_stations', (SELECT COUNT(*) FROM stations s WHERE s.supervisor_id = p.id)
      ) ORDER BY p.full_name ASC
    )
    FROM profiles p
    WHERE (p.org_id = p_org_id OR p_org_id IS NULL)
      AND p.role = 'supervisor'
  ), '[]'::JSONB);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Function to transfer all data (stations, shifts) from one supervisor to another
CREATE OR REPLACE FUNCTION public.admin_transfer_supervisor_data(
  p_from_supervisor_id UUID,
  p_to_supervisor_id UUID,
  p_org_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_stations_count INT := 0;
  v_shifts_count INT := 0;
BEGIN
  -- Reassign stations
  UPDATE stations
  SET supervisor_id = p_to_supervisor_id
  WHERE supervisor_id = p_from_supervisor_id 
    AND (org_id = p_org_id OR p_org_id IS NULL);
  GET DIAGNOSTICS v_stations_count = ROW_COUNT;

  -- Reassign shifts
  UPDATE shifts
  SET supervisor_id = p_to_supervisor_id
  WHERE supervisor_id = p_from_supervisor_id 
    AND (org_id = p_org_id OR p_org_id IS NULL);
  GET DIAGNOSTICS v_shifts_count = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true,
    'transferred_stations', v_stations_count,
    'transferred_shifts', v_shifts_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Grant execution permissions
GRANT EXECUTE ON FUNCTION public.get_org_supervisors(UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_transfer_supervisor_data(UUID, UUID, UUID) TO anon, authenticated, service_role;

-- 4. Reload PostgREST schema cache immediately
NOTIFY pgrst, 'reload schema';


-- 1. Wipe All Operational & Shift Data
TRUNCATE TABLE attendance CASCADE;
TRUNCATE TABLE punch_sessions CASCADE;
TRUNCATE TABLE shift_assignments CASCADE;
TRUNCATE TABLE shifts CASCADE;
TRUNCATE TABLE station_shift_templates CASCADE;
TRUNCATE TABLE station_operating_systems CASCADE;
TRUNCATE TABLE stations CASCADE;

-- 2. Wipe All Staff & Supervisor Profiles (Clean Slate)
DELETE FROM profiles;
DELETE FROM auth.identities;
DELETE FROM auth.users;

-- 3. Ensure Master Organization Exists
INSERT INTO organizations (id, name)
VALUES ('00000000-0000-0000-0000-000000000001', 'Metro Shift Roster')
ON CONFLICT (id) DO UPDATE SET name = 'Metro Shift Roster';

-- 4. Create Single Real Admin Account
INSERT INTO profiles (
  id,
  org_id,
  role,
  phone_number,
  full_name,
  email,
  password_hash,
  pin_hash,
  has_pin,
  is_active
) VALUES (
  '00000000-0000-0000-0000-000000000099',
  '00000000-0000-0000-0000-000000000001',
  'admin',
  '9999999999',
  'Central Administrator',
  'puneet56511@gmail.com',
  crypt('1234', gen_salt('bf', 10)),
  '1234',
  TRUE,
  TRUE
);

-- 5. RPC to Fetch All Supervisors with Organization Summary Stats
CREATE OR REPLACE FUNCTION public.get_org_supervisors_overview(p_org_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_total_stations INT := 0;
  v_total_operators INT := 0;
BEGIN
  SELECT COUNT(*) INTO v_total_stations FROM stations WHERE (org_id = p_org_id OR p_org_id IS NULL);
  SELECT COUNT(*) INTO v_total_operators FROM profiles WHERE (org_id = p_org_id OR p_org_id IS NULL) AND role = 'tom_operator' AND is_active = TRUE;

  RETURN COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'full_name', p.full_name,
        'phone_number', p.phone_number,
        'email', p.email,
        'is_active', p.is_active,
        'created_at', p.created_at,
        'total_stations', v_total_stations,
        'total_operators', v_total_operators
      ) ORDER BY p.full_name ASC
    )
    FROM profiles p
    WHERE (p.org_id = p_org_id OR p_org_id IS NULL)
      AND p.role = 'supervisor'
  ), '[]'::JSONB);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_org_supervisors_overview(UUID) TO anon, authenticated, service_role;
NOTIFY pgrst, 'reload schema';



-- 1. Enable pgcrypto for PIN hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Clear all hardcoded PINs across profiles (forces dynamic user setup)
UPDATE profiles
SET pin_hash = NULL,
    has_pin = FALSE
WHERE role != 'admin';

-- 3. Secure RPC to register a user's self-chosen custom PIN
CREATE OR REPLACE FUNCTION set_user_custom_pin(p_user_id UUID, p_pin TEXT)
RETURNS JSONB AS $$
BEGIN
  IF length(p_pin) != 4 THEN
    RETURN jsonb_build_object('success', false, 'error', 'PIN must be exactly 4 digits.');
  END IF;

  UPDATE profiles
  SET pin_hash = crypt(p_pin, gen_salt('bf', 8)),
      has_pin = TRUE,
      updated_at = NOW()
  WHERE id = p_user_id;

  RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Secure RPC to verify user's custom hashed PIN
CREATE OR REPLACE FUNCTION verify_user_custom_pin(p_user_id UUID, p_pin TEXT)
RETURNS JSONB AS $$
DECLARE
  v_stored_hash TEXT;
  v_has_pin BOOLEAN;
BEGIN
  SELECT pin_hash, COALESCE(has_pin, false)
  INTO v_stored_hash, v_has_pin
  FROM profiles
  WHERE id = p_user_id AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'User account not found.');
  END IF;

  IF NOT v_has_pin OR v_stored_hash IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'PIN not set. Please complete verification setup.');
  END IF;

  IF v_stored_hash = crypt(p_pin, v_stored_hash) THEN
    RETURN jsonb_build_object('success', true);
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Incorrect PIN. Please try again.');
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION set_user_custom_pin(UUID, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION verify_user_custom_pin(UUID, TEXT) TO anon, authenticated, service_role;


-- 1. Drop old functions to avoid signature conflicts
DROP FUNCTION IF EXISTS public.register_user_face(UUID, JSONB);
DROP FUNCTION IF EXISTS public.verify_registered_face_embedding(UUID, JSONB);
DROP FUNCTION IF EXISTS public.process_face_punch_record(UUID, UUID, UUID, UUID, BOOLEAN, JSONB);

-- 2. 1-Click Single Photo Face Registration RPC
CREATE OR REPLACE FUNCTION public.register_user_face(
  p_user_id UUID,
  p_embedding JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_embedding IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid face biometric template.');
  END IF;

  UPDATE public.profiles
  SET face_embedding = p_embedding,
      is_face_registered = TRUE,
      updated_at = NOW()
  WHERE id = p_user_id
    AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Active user profile not found.');
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'user_id', p_user_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_user_face(UUID, JSONB) TO anon, authenticated, service_role;

-- 3. Live Biometric Matching RPC (Handles Single or Multiple Vector Formats)
CREATE OR REPLACE FUNCTION public.verify_registered_face_embedding(
  p_user_id UUID,
  p_live_embedding JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stored JSONB;
  v_sample JSONB;
  v_len INTEGER;
  v_i INTEGER;
  v_live NUMERIC;
  v_ref NUMERIC;
  v_dot NUMERIC;
  v_norm_live NUMERIC;
  v_norm_ref NUMERIC;
  v_similarity DOUBLE PRECISION;
  v_best DOUBLE PRECISION := -1.0;
  v_matched BOOLEAN := FALSE;
  v_threshold CONSTANT DOUBLE PRECISION := 0.60;
BEGIN
  IF p_live_embedding IS NULL
     OR jsonb_typeof(p_live_embedding) <> 'array' THEN
    RETURN jsonb_build_object('success', FALSE, 'matched', FALSE, 'error', 'Invalid live face embedding.');
  END IF;

  SELECT face_embedding
  INTO v_stored
  FROM public.profiles
  WHERE id = p_user_id
    AND is_active = TRUE
    AND COALESCE(is_face_registered, FALSE) = TRUE;

  IF v_stored IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'matched', FALSE, 'error', 'Face is not registered for this account.');
  END IF;

  -- Support both single vector format and legacy arrays
  IF jsonb_typeof(v_stored -> 'embeddings') = 'array' THEN
    v_sample := (v_stored -> 'embeddings') -> 0;
  ELSE
    v_sample := v_stored -> 'embedding';
  END IF;

  IF v_sample IS NULL OR jsonb_typeof(v_sample) <> 'array' THEN
    v_sample := v_stored;
  END IF;

  v_len := jsonb_array_length(p_live_embedding);
  v_dot := 0;
  v_norm_live := 0;
  v_norm_ref := 0;

  FOR v_i IN 0..(v_len - 1)
  LOOP
    BEGIN
      v_live := (p_live_embedding -> v_i)::TEXT::NUMERIC;
      v_ref := (v_sample -> v_i)::TEXT::NUMERIC;
    EXCEPTION WHEN OTHERS THEN
      v_live := NULL;
      v_ref := NULL;
    END;

    IF v_live IS NULL OR v_ref IS NULL THEN
      v_dot := 0;
      v_norm_live := 0;
      v_norm_ref := 0;
      EXIT;
    END IF;

    v_dot := v_dot + (v_live * v_ref);
    v_norm_live := v_norm_live + (v_live * v_live);
    v_norm_ref := v_norm_ref + (v_ref * v_ref);
  END LOOP;

  IF v_norm_live > 0 AND v_norm_ref > 0 THEN
    v_similarity := v_dot::DOUBLE PRECISION /
      (sqrt(v_norm_live::DOUBLE PRECISION) * sqrt(v_norm_ref::DOUBLE PRECISION));
    v_best := v_similarity;
  END IF;

  v_matched := v_best >= v_threshold;

  RETURN jsonb_build_object(
    'success', TRUE,
    'matched', v_matched,
    'similarity', v_best,
    'threshold', v_threshold
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_registered_face_embedding(UUID, JSONB) TO anon, authenticated, service_role;

-- 4. Biometric Punch RPC
CREATE OR REPLACE FUNCTION public.process_face_punch_record(
  p_session_id UUID,
  p_user_id UUID,
  p_org_id UUID,
  p_station_id UUID,
  p_is_punch_in BOOLEAN,
  p_face_embedding JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_verify JSONB;
  v_session_id UUID;
  v_fixed_amount NUMERIC(10,2);
BEGIN
  v_verify := public.verify_registered_face_embedding(p_user_id, p_face_embedding);

  IF (v_verify ->> 'success')::BOOLEAN IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', v_verify ->> 'error');
  END IF;

  IF (v_verify ->> 'matched')::BOOLEAN IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false, 
      'error', 'Face does not match registered account! (Similarity: ' || ROUND((v_verify ->> 'similarity')::NUMERIC, 2) || ')'
    );
  END IF;

  IF p_is_punch_in THEN
    INSERT INTO public.punch_sessions (
      org_id, operator_id, station_id, duty_date, punch_in_at, punch_in_verified, status
    ) VALUES (
      p_org_id, p_user_id, p_station_id, CURRENT_DATE, NOW(), TRUE, 'in_progress'
    ) RETURNING id INTO v_session_id;

    RETURN jsonb_build_object('success', true, 'session_id', v_session_id, 'action', 'PUNCH_IN');
  ELSE
    SELECT default_fixed_amount INTO v_fixed_amount FROM public.stations WHERE id = p_station_id;

    UPDATE public.punch_sessions
    SET punch_out_at = NOW(),
        punch_out_verified = TRUE,
        status = 'completed',
        updated_at = NOW()
    WHERE id = p_session_id;

    INSERT INTO public.attendance (
      org_id, operator_id, station_id, duty_date, status, is_ot, earnings
    ) VALUES (
      p_org_id, p_user_id, p_station_id, CURRENT_DATE, 'present', FALSE, COALESCE(v_fixed_amount, 700.00)
    )
    ON CONFLICT (operator_id, duty_date)
    DO UPDATE SET status = 'present', earnings = COALESCE(v_fixed_amount, 700.00);

    RETURN jsonb_build_object('success', true, 'action', 'PUNCH_OUT');
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_face_punch_record(UUID, UUID, UUID, UUID, BOOLEAN, JSONB) TO anon, authenticated, service_role;

-- Recreate the Biometric Punch RPC with coordinate inputs
CREATE OR REPLACE FUNCTION public.process_face_punch_record(
  p_session_id UUID,
  p_user_id UUID,
  p_org_id UUID,
  p_station_id UUID,
  p_is_punch_in BOOLEAN,
  p_face_embedding JSONB,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lng DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_verify JSONB;
  v_station public.stations%ROWTYPE;
  v_session_id UUID;
  v_lat DOUBLE PRECISION;
  v_lng DOUBLE PRECISION;
  v_fixed_amount NUMERIC(10,2);
BEGIN
  -- 1. Biometric verification
  v_verify := public.verify_registered_face_embedding(p_user_id, p_face_embedding);

  IF (v_verify ->> 'success')::BOOLEAN IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', v_verify ->> 'error');
  END IF;

  IF (v_verify ->> 'matched')::BOOLEAN IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false, 
      'error', 'Face does not match registered account! (Similarity: ' || ROUND((v_verify ->> 'similarity')::NUMERIC, 2) || ')'
    );
  END IF;

  -- 2. Fetch station details for coordinates fallback & amount
  SELECT * INTO v_station FROM public.stations WHERE id = p_station_id;
  v_lat := COALESCE(p_lat, v_station.latitude, 12.9716);
  v_lng := COALESCE(p_lng, v_station.longitude, 77.5946);
  v_fixed_amount := COALESCE(v_station.default_fixed_amount, 700.00);

  -- 3. Process Punch In / Punch Out
  IF p_is_punch_in THEN
    INSERT INTO public.punch_sessions (
      org_id,
      operator_id,
      station_id,
      duty_date,
      punch_in_at,
      punch_in_lat,
      punch_in_lng,
      punch_in_verified,
      status
    ) VALUES (
      p_org_id,
      p_user_id,
      p_station_id,
      CURRENT_DATE,
      NOW(),
      v_lat,
      v_lng,
      TRUE,
      'in_progress'
    ) RETURNING id INTO v_session_id;

    RETURN jsonb_build_object('success', true, 'session_id', v_session_id, 'action', 'PUNCH_IN');
  ELSE
    UPDATE public.punch_sessions
    SET punch_out_at = NOW(),
        punch_out_lat = v_lat,
        punch_out_lng = v_lng,
        punch_out_verified = TRUE,
        status = 'completed',
        updated_at = NOW()
    WHERE id = p_session_id;

    INSERT INTO public.attendance (
      org_id,
      operator_id,
      station_id,
      duty_date,
      status,
      is_ot,
      earnings
    ) VALUES (
      p_org_id,
      p_user_id,
      p_station_id,
      CURRENT_DATE,
      'present',
      FALSE,
      v_fixed_amount
    )
    ON CONFLICT (operator_id, duty_date)
    DO UPDATE SET status = 'present', earnings = v_fixed_amount;

    RETURN jsonb_build_object('success', true, 'action', 'PUNCH_OUT');
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_face_punch_record(UUID, UUID, UUID, UUID, BOOLEAN, JSONB, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;


-- 1. Create a safe unique constraint on (operator_id, station_id, duty_date)
CREATE UNIQUE INDEX IF NOT EXISTS attendance_operator_station_date_idx 
ON public.attendance (operator_id, station_id, duty_date);

-- 2. Update the hardened RPC function to handle Punch In and Punch Out safely
CREATE OR REPLACE FUNCTION public.process_face_punch_record(
  p_session_id TEXT,
  p_user_id UUID,
  p_org_id UUID,
  p_station_id UUID,
  p_is_punch_in BOOLEAN,
  p_face_embedding TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_is_mocked BOOLEAN,
  p_accuracy DOUBLE PRECISION
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_station_lat DOUBLE PRECISION;
  v_station_lng DOUBLE PRECISION;
  v_radius DOUBLE PRECISION;
  v_distance DOUBLE PRECISION;
  v_existing_id UUID;
  v_shift_id UUID;
BEGIN
  -- 1. Reject mock location
  IF p_is_mocked THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mock location detected. Punch rejected.');
  END IF;

  -- 2. Fetch Station Geofence Coordinates
  SELECT latitude, longitude, COALESCE(punch_radius_meters, 600)
  INTO v_station_lat, v_station_lng, v_radius
  FROM public.stations
  WHERE id = p_station_id;

  -- Calculate distance using Haversine formula (meters)
  IF v_station_lat IS NOT NULL AND v_station_lng IS NOT NULL THEN
    v_distance := (
      6371000 * acos(
        least(1.0, greatest(-1.0, 
          cos(radians(v_station_lat)) * cos(radians(p_lat)) * 
          cos(radians(p_lng) - radians(v_station_lng)) + 
          sin(radians(v_station_lat)) * sin(radians(p_lat))
        ))
      )
    );

    IF v_distance > v_radius THEN
      RETURN jsonb_build_object(
        'success', false, 
        'error', format('Out of station geofence boundary (%sm away, limit is %sm)', round(v_distance::numeric, 1), v_radius)
      );
    END IF;
  ELSE
    v_distance := 0;
  END IF;

  -- 3. Find today's assigned shift for this operator & station
  SELECT s.id INTO v_shift_id
  FROM public.shift_assignments sa
  JOIN public.shifts s ON s.id = sa.shift_id
  WHERE sa.operator_id = p_user_id 
    AND s.station_id = p_station_id 
    AND s.duty_date = v_today
  LIMIT 1;

  -- 4. Execute Punch In / Punch Out
  IF p_is_punch_in THEN
    -- Check if record already exists for today
    SELECT id INTO v_existing_id
    FROM public.attendance
    WHERE operator_id = p_user_id 
      AND station_id = p_station_id 
      AND duty_date = v_today
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      UPDATE public.attendance SET
        punch_in_time = NOW(),
        punch_in_lat = p_lat,
        punch_in_lng = p_lng,
        face_confidence = 1.0,
        status = 'present',
        updated_at = NOW()
      WHERE id = v_existing_id;
    ELSE
      INSERT INTO public.attendance (
        org_id,
        operator_id,
        station_id,
        shift_id,
        duty_date,
        punch_in_time,
        punch_in_lat,
        punch_in_lng,
        face_confidence,
        status
      ) VALUES (
        p_org_id,
        p_user_id,
        p_station_id,
        v_shift_id,
        v_today,
        NOW(),
        p_lat,
        p_lng,
        1.0,
        'present'
      );
    END IF;

    RETURN jsonb_build_object('success', true, 'distance', round(v_distance::numeric, 1));
  ELSE
    -- Punch Out: locate existing active punch
    SELECT id INTO v_existing_id
    FROM public.attendance
    WHERE operator_id = p_user_id 
      AND station_id = p_station_id 
      AND duty_date = v_today
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      UPDATE public.attendance SET
        punch_out_time = NOW(),
        punch_out_lat = p_lat,
        punch_out_lng = p_lng,
        status = 'completed',
        updated_at = NOW()
      WHERE id = v_existing_id;
    ELSE
      INSERT INTO public.attendance (
        org_id,
        operator_id,
        station_id,
        shift_id,
        duty_date,
        punch_out_time,
        punch_out_lat,
        punch_out_lng,
        status
      ) VALUES (
        p_org_id,
        p_user_id,
        p_station_id,
        v_shift_id,
        v_today,
        NOW(),
        p_lat,
        p_lng,
        'completed'
      );
    END IF;

    RETURN jsonb_build_object('success', true, 'distance', round(v_distance::numeric, 1));
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';


-- =================================================================
-- 1. DROP ALL OLD OVERLOADED VERSIONS OF process_face_punch_record
-- =================================================================
DO $$ 
DECLARE 
    r RECORD;
BEGIN
    FOR r IN (
        SELECT oid::regprocedure AS func_signature
        FROM pg_proc
        WHERE proname = 'process_face_punch_record'
          AND pronamespace = 'public'::regnamespace
    ) LOOP
        EXECUTE 'DROP FUNCTION ' || r.func_signature || ' CASCADE;';
    END LOOP;
END $$;

-- =================================================================
-- 2. CREATE CLEAN process_face_punch_record FUNCTION
-- =================================================================
CREATE OR REPLACE FUNCTION public.process_face_punch_record(
  p_session_id TEXT,
  p_user_id UUID,
  p_org_id UUID,
  p_station_id UUID,
  p_is_punch_in BOOLEAN,
  p_face_embedding TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_is_mocked BOOLEAN,
  p_accuracy DOUBLE PRECISION
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_station_lat DOUBLE PRECISION;
  v_station_lng DOUBLE PRECISION;
  v_radius DOUBLE PRECISION;
  v_distance DOUBLE PRECISION;
  v_existing_id UUID;
  v_shift_id UUID;
BEGIN
  -- 1. Reject mock location
  IF p_is_mocked THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mock location detected. Punch rejected.');
  END IF;

  -- 2. Check station geofence
  SELECT latitude, longitude, COALESCE(punch_radius_meters, 600)
  INTO v_station_lat, v_station_lng, v_radius
  FROM public.stations
  WHERE id = p_station_id;

  IF v_station_lat IS NOT NULL AND v_station_lng IS NOT NULL THEN
    v_distance := (
      6371000 * acos(
        least(1.0, greatest(-1.0, 
          cos(radians(v_station_lat)) * cos(radians(p_lat)) * 
          cos(radians(p_lng) - radians(v_station_lng)) + 
          sin(radians(v_station_lat)) * sin(radians(p_lat))
        ))
      )
    );

    IF v_distance > v_radius THEN
      RETURN jsonb_build_object(
        'success', false, 
        'error', format('Out of station boundary (%sm away, limit %sm)', round(v_distance::numeric, 1), v_radius)
      );
    END IF;
  ELSE
    v_distance := 0;
  END IF;

  -- 3. Resolve shift id for today
  SELECT s.id INTO v_shift_id
  FROM public.shift_assignments sa
  JOIN public.shifts s ON s.id = sa.shift_id
  WHERE sa.operator_id = p_user_id 
    AND s.station_id = p_station_id 
    AND s.duty_date = v_today
  LIMIT 1;

  -- 4. Punch In or Out
  IF p_is_punch_in THEN
    SELECT id INTO v_existing_id
    FROM public.attendance
    WHERE operator_id = p_user_id 
      AND station_id = p_station_id 
      AND duty_date = v_today
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      UPDATE public.attendance SET
        punch_in_time = NOW(),
        punch_in_lat = p_lat,
        punch_in_lng = p_lng,
        face_confidence = 1.0,
        status = 'present',
        updated_at = NOW()
      WHERE id = v_existing_id;
    ELSE
      INSERT INTO public.attendance (
        org_id,
        operator_id,
        station_id,
        shift_id,
        duty_date,
        punch_in_time,
        punch_in_lat,
        punch_in_lng,
        face_confidence,
        status
      ) VALUES (
        p_org_id,
        p_user_id,
        p_station_id,
        v_shift_id,
        v_today,
        NOW(),
        p_lat,
        p_lng,
        1.0,
        'present'
      );
    END IF;
  ELSE
    SELECT id INTO v_existing_id
    FROM public.attendance
    WHERE operator_id = p_user_id 
      AND station_id = p_station_id 
      AND duty_date = v_today
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      UPDATE public.attendance SET
        punch_out_time = NOW(),
        punch_out_lat = p_lat,
        punch_out_lng = p_lng,
        status = 'completed',
        updated_at = NOW()
      WHERE id = v_existing_id;
    ELSE
      INSERT INTO public.attendance (
        org_id,
        operator_id,
        station_id,
        shift_id,
        duty_date,
        punch_out_time,
        punch_out_lat,
        punch_out_lng,
        status
      ) VALUES (
        p_org_id,
        p_user_id,
        p_station_id,
        v_shift_id,
        v_today,
        NOW(),
        p_lat,
        p_lng,
        'completed'
      );
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'distance', round(v_distance::numeric, 1));
END;
$$;

-- =================================================================
-- 3. FIX get_operator_dashboard_overview (REMOVING a.assignment_id)
-- =================================================================
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

  -- 3. Completed Duties (Both punch in and punch out present)
  SELECT COUNT(id)
  INTO v_completed_duty
  FROM public.attendance
  WHERE operator_id = p_operator_id
    AND punch_in_time IS NOT NULL
    AND punch_out_time IS NOT NULL;

  -- 4. Completed OT Duties (Joined via shift_id and operator_id)
  SELECT COUNT(a.id)
  INTO v_total_ot
  FROM public.attendance a
  JOIN public.shift_assignments sa 
    ON sa.shift_id = a.shift_id AND sa.operator_id = a.operator_id
  WHERE a.operator_id = p_operator_id
    AND a.punch_in_time IS NOT NULL
    AND a.punch_out_time IS NOT NULL
    AND sa.is_ot = true;

  -- 5. Total Earnings from Completed Duties
  SELECT COALESCE(SUM(s.daily_amount), 0)
  INTO v_total_earnings
  FROM public.attendance a
  JOIN public.shifts s ON s.id = a.shift_id
  WHERE a.operator_id = p_operator_id
    AND a.punch_in_time IS NOT NULL
    AND a.punch_out_time IS NOT NULL;

  -- 6. Week Offs
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

-- Reload Supabase Schema Cache
NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';

-- Set timezone to Asia/Kolkata for all date operations
SET TIME ZONE 'Asia/Kolkata';

CREATE OR REPLACE FUNCTION public.process_face_punch_record(
  p_session_id TEXT,
  p_user_id UUID,
  p_org_id UUID,
  p_station_id UUID,
  p_is_punch_in BOOLEAN,
  p_face_embedding TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_is_mocked BOOLEAN,
  p_accuracy DOUBLE PRECISION
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_now_ist TIMESTAMP WITH TIME ZONE := NOW() AT TIME ZONE 'Asia/Kolkata';
  v_today_ist DATE := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_station_lat DOUBLE PRECISION;
  v_station_lng DOUBLE PRECISION;
  v_radius DOUBLE PRECISION;
  v_distance DOUBLE PRECISION := 0;
  v_existing_id UUID;
  v_shift_id UUID;
BEGIN
  IF p_is_mocked THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mock GPS detected. Punch rejected.');
  END IF;

  -- Station geofence
  SELECT latitude, longitude, COALESCE(punch_radius_meters, 600)
  INTO v_station_lat, v_station_lng, v_radius
  FROM public.stations
  WHERE id = p_station_id;

  IF v_station_lat IS NOT NULL AND v_station_lng IS NOT NULL THEN
    v_distance := (
      6371000 * acos(
        least(1.0, greatest(-1.0, 
          cos(radians(v_station_lat)) * cos(radians(p_lat)) * 
          cos(radians(p_lng) - radians(v_station_lng)) + 
          sin(radians(v_station_lat)) * sin(radians(p_lat))
        ))
      )
    );

    IF v_distance > v_radius THEN
      RETURN jsonb_build_object(
        'success', false, 
        'error', format('Out of station boundary (%sm away, allowed %sm)', round(v_distance::numeric, 1), v_radius)
      );
    END IF;
  END IF;

  -- 1. Check for any active open punch-in (within past 24 hours IST)
  SELECT id, shift_id INTO v_existing_id, v_shift_id
  FROM public.attendance
  WHERE operator_id = p_user_id 
    AND punch_out_time IS NULL
  ORDER BY punch_in_time DESC
  LIMIT 1;

  IF p_is_punch_in THEN
    IF v_existing_id IS NOT NULL THEN
      -- Already punched in
      RETURN jsonb_build_object('success', false, 'error', 'You already have an active Punch In! Please Punch Out first.');
    END IF;

    -- Find shift assigned for today or nearest shift
    SELECT s.id INTO v_shift_id
    FROM public.shift_assignments sa
    JOIN public.shifts s ON s.id = sa.shift_id
    WHERE sa.operator_id = p_user_id 
      AND s.station_id = p_station_id 
      AND (s.duty_date = v_today_ist OR s.duty_date = (v_today_ist - INTERVAL '1 day')::DATE)
    ORDER BY s.duty_date DESC
    LIMIT 1;

    INSERT INTO public.attendance (
      org_id,
      operator_id,
      station_id,
      shift_id,
      duty_date,
      punch_in_time,
      punch_in_lat,
      punch_in_lng,
      face_confidence,
      status
    ) VALUES (
      p_org_id,
      p_user_id,
      p_station_id,
      v_shift_id,
      v_today_ist,
      v_now_ist,
      p_lat,
      p_lng,
      1.0,
      'present'
    );

    RETURN jsonb_build_object('success', true, 'distance', round(v_distance::numeric, 1));
  ELSE
    -- PUNCH OUT
    IF v_existing_id IS NOT NULL THEN
      UPDATE public.attendance SET
        punch_out_time = v_now_ist,
        punch_out_lat = p_lat,
        punch_out_lng = p_lng,
        status = 'completed',
        updated_at = v_now_ist
      WHERE id = v_existing_id;
    ELSE
      -- Fallback: update most recent record from today or yesterday
      UPDATE public.attendance SET
        punch_out_time = v_now_ist,
        punch_out_lat = p_lat,
        punch_out_lng = p_lng,
        status = 'completed',
        updated_at = v_now_ist
      WHERE id = (
        SELECT id FROM public.attendance
        WHERE operator_id = p_user_id
        ORDER BY created_at DESC LIMIT 1
      );
    END IF;

    RETURN jsonb_build_object('success', true, 'distance', round(v_distance::numeric, 1));
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';



-- 1. Add missing audit columns to attendance table
ALTER TABLE public.attendance 
ADD COLUMN IF NOT EXISTS punch_in_lat DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS punch_in_lng DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS punch_out_lat DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS punch_out_lng DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS face_confidence DOUBLE PRECISION DEFAULT 1.0,
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'present',
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- 2. Ensure permissions and reload PostgREST schema cache
GRANT ALL ON public.attendance TO authenticated, anon;
NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';


-- 1. Convert status column to plain TEXT to eliminate ENUM mismatch errors
ALTER TABLE public.attendance ALTER COLUMN status TYPE TEXT USING status::TEXT;
ALTER TABLE public.attendance ALTER COLUMN status SET DEFAULT 'present';

-- Optional: add value to enum if used elsewhere
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'attendance_status') THEN
    BEGIN
      ALTER TYPE attendance_status ADD VALUE IF NOT EXISTS 'completed';
    EXCEPTION
      WHEN duplicate_object THEN null;
    END;
  END IF;
END $$;

-- 2. Update process_face_punch_record with standard UTC timestamps (Flutter converts to IST accurately)
CREATE OR REPLACE FUNCTION public.process_face_punch_record(
  p_session_id TEXT,
  p_user_id UUID,
  p_org_id UUID,
  p_station_id UUID,
  p_is_punch_in BOOLEAN,
  p_face_embedding TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_is_mocked BOOLEAN,
  p_accuracy DOUBLE PRECISION
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_station_lat DOUBLE PRECISION;
  v_station_lng DOUBLE PRECISION;
  v_radius DOUBLE PRECISION;
  v_distance DOUBLE PRECISION := 0;
  v_existing_id UUID;
  v_shift_id UUID;
BEGIN
  -- 1. Check mock GPS
  IF p_is_mocked THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mock GPS detected. Punch rejected.');
  END IF;

  -- 2. Check station geofence
  SELECT latitude, longitude, COALESCE(punch_radius_meters, 600)
  INTO v_station_lat, v_station_lng, v_radius
  FROM public.stations
  WHERE id = p_station_id;

  IF v_station_lat IS NOT NULL AND v_station_lng IS NOT NULL THEN
    v_distance := (
      6371000 * acos(
        least(1.0, greatest(-1.0, 
          cos(radians(v_station_lat)) * cos(radians(p_lat)) * 
          cos(radians(p_lng) - radians(v_station_lng)) + 
          sin(radians(v_station_lat)) * sin(radians(p_lat))
        ))
      )
    );

    IF v_distance > v_radius THEN
      RETURN jsonb_build_object(
        'success', false, 
        'error', format('Out of station boundary (%sm away, allowed %sm)', round(v_distance::numeric, 1), v_radius)
      );
    END IF;
  END IF;

  -- 3. Check for any active open punch-in
  SELECT id, shift_id INTO v_existing_id, v_shift_id
  FROM public.attendance
  WHERE operator_id = p_user_id 
    AND punch_out_time IS NULL
  ORDER BY punch_in_time DESC
  LIMIT 1;

  IF p_is_punch_in THEN
    IF v_existing_id IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'You already have an active Punch In! Please Punch Out first.');
    END IF;

    -- Match today's shift
    SELECT s.id INTO v_shift_id
    FROM public.shift_assignments sa
    JOIN public.shifts s ON s.id = sa.shift_id
    WHERE sa.operator_id = p_user_id 
      AND s.station_id = p_station_id 
      AND (s.duty_date = v_today OR s.duty_date = (v_today - INTERVAL '1 day')::DATE)
    ORDER BY s.duty_date DESC
    LIMIT 1;

    INSERT INTO public.attendance (
      org_id,
      operator_id,
      station_id,
      shift_id,
      duty_date,
      punch_in_time,
      punch_in_lat,
      punch_in_lng,
      face_confidence,
      status
    ) VALUES (
      p_org_id,
      p_user_id,
      p_station_id,
      v_shift_id,
      v_today,
      NOW(),
      p_lat,
      p_lng,
      1.0,
      'present'
    );

    RETURN jsonb_build_object('success', true, 'distance', round(v_distance::numeric, 1));
  ELSE
    -- PUNCH OUT
    IF v_existing_id IS NOT NULL THEN
      UPDATE public.attendance SET
        punch_out_time = NOW(),
        punch_out_lat = p_lat,
        punch_out_lng = p_lng,
        status = 'completed',
        updated_at = NOW()
      WHERE id = v_existing_id;
    ELSE
      -- Fallback: update most recent punch record
      UPDATE public.attendance SET
        punch_out_time = NOW(),
        punch_out_lat = p_lat,
        punch_out_lng = p_lng,
        status = 'completed',
        updated_at = NOW()
      WHERE id = (
        SELECT id FROM public.attendance
        WHERE operator_id = p_user_id
        ORDER BY created_at DESC LIMIT 1
      );
    END IF;

    RETURN jsonb_build_object('success', true, 'distance', round(v_distance::numeric, 1));
  END IF;
END;
$$;

NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';


-- 1. Drop the restrictive station+date unique constraint
DROP INDEX IF EXISTS public.attendance_operator_station_date_idx;

-- 2. Update process_face_punch_record to link punches to active sessions cleanly
CREATE OR REPLACE FUNCTION public.process_face_punch_record(
  p_session_id TEXT,
  p_user_id UUID,
  p_org_id UUID,
  p_station_id UUID,
  p_is_punch_in BOOLEAN,
  p_face_embedding TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_is_mocked BOOLEAN,
  p_accuracy DOUBLE PRECISION
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_station_lat DOUBLE PRECISION;
  v_station_lng DOUBLE PRECISION;
  v_radius DOUBLE PRECISION;
  v_distance DOUBLE PRECISION := 0;
  v_existing_id UUID;
  v_shift_id UUID;
BEGIN
  -- Check mock GPS
  IF p_is_mocked THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mock GPS detected. Punch rejected.');
  END IF;

  -- Verify station geofence
  SELECT latitude, longitude, COALESCE(punch_radius_meters, 600)
  INTO v_station_lat, v_station_lng, v_radius
  FROM public.stations
  WHERE id = p_station_id;

  IF v_station_lat IS NOT NULL AND v_station_lng IS NOT NULL THEN
    v_distance := (
      6371000 * acos(
        least(1.0, greatest(-1.0, 
          cos(radians(v_station_lat)) * cos(radians(p_lat)) * 
          cos(radians(p_lng) - radians(v_station_lng)) + 
          sin(radians(v_station_lat)) * sin(radians(p_lat))
        ))
      )
    );

    IF v_distance > v_radius THEN
      RETURN jsonb_build_object(
        'success', false, 
        'error', format('Out of station boundary (%sm away, allowed %sm)', round(v_distance::numeric, 1), v_radius)
      );
    END IF;
  END IF;

  -- Locate shift assigned for today or yesterday (for night shifts)
  SELECT s.id INTO v_shift_id
  FROM public.shift_assignments sa
  JOIN public.shifts s ON s.id = sa.shift_id
  WHERE sa.operator_id = p_user_id 
    AND s.station_id = p_station_id 
    AND (s.duty_date = v_today OR s.duty_date = (v_today - INTERVAL '1 day')::DATE)
  ORDER BY s.duty_date DESC
  LIMIT 1;

  IF p_is_punch_in THEN
    -- Check if there is an unclosed punch
    SELECT id INTO v_existing_id
    FROM public.attendance
    WHERE operator_id = p_user_id 
      AND punch_out_time IS NULL
    ORDER BY punch_in_time DESC
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'You have an active Punch In session. Please Punch Out first.');
    END IF;

    -- Insert new punch-in record
    INSERT INTO public.attendance (
      org_id,
      operator_id,
      station_id,
      shift_id,
      duty_date,
      punch_in_time,
      punch_in_lat,
      punch_in_lng,
      face_confidence,
      status
    ) VALUES (
      p_org_id,
      p_user_id,
      p_station_id,
      v_shift_id,
      v_today,
      NOW(),
      p_lat,
      p_lng,
      1.0,
      'present'
    );

    RETURN jsonb_build_object('success', true, 'distance', round(v_distance::numeric, 1));
  ELSE
    -- PUNCH OUT: Match specific session ID if passed, otherwise grab the active unclosed punch
    IF p_session_id IS NOT NULL AND p_session_id != '' THEN
      SELECT id INTO v_existing_id
      FROM public.attendance
      WHERE id = p_session_id::UUID;
    ELSE
      SELECT id INTO v_existing_id
      FROM public.attendance
      WHERE operator_id = p_user_id 
        AND punch_out_time IS NULL
      ORDER BY punch_in_time DESC
      LIMIT 1;
    END IF;

    IF v_existing_id IS NOT NULL THEN
      UPDATE public.attendance SET
        punch_out_time = NOW(),
        punch_out_lat = p_lat,
        punch_out_lng = p_lng,
        status = 'completed',
        updated_at = NOW()
      WHERE id = v_existing_id;
    ELSE
      -- Fallback update for most recent record
      UPDATE public.attendance SET
        punch_out_time = NOW(),
        punch_out_lat = p_lat,
        punch_out_lng = p_lng,
        status = 'completed',
        updated_at = NOW()
      WHERE id = (
        SELECT id FROM public.attendance
        WHERE operator_id = p_user_id
        ORDER BY created_at DESC LIMIT 1
      );
    END IF;

    RETURN jsonb_build_object('success', true, 'distance', round(v_distance::numeric, 1));
  END IF;
END;
$$;

NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';


-- Drop the remaining restrictive index
DROP INDEX IF EXISTS public.attendance_operator_shift_date_idx;

-- Reload Schema Cache
NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';



CREATE OR REPLACE FUNCTION public.process_face_punch_record(
  p_session_id TEXT,
  p_user_id UUID,
  p_org_id UUID,
  p_station_id UUID,
  p_is_punch_in BOOLEAN,
  p_face_embedding TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_is_mocked BOOLEAN,
  p_accuracy DOUBLE PRECISION
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_station_lat DOUBLE PRECISION;
  v_station_lng DOUBLE PRECISION;
  v_radius DOUBLE PRECISION;
  v_distance DOUBLE PRECISION := 0;
  v_existing_id UUID;
  v_shift_id UUID;
  v_punch_in_time TIMESTAMPTZ;
  v_duty_duration INT := 0;
  v_status TEXT := 'absent';
  v_shift_rate NUMERIC := 0;
  v_earned_amount NUMERIC := 0;
BEGIN
  -- 1. Mock GPS Check
  IF p_is_mocked THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mock GPS detected. Punch rejected.');
  END IF;

  -- 2. Station Boundary Check
  SELECT latitude, longitude, COALESCE(punch_radius_meters, 600)
  INTO v_station_lat, v_station_lng, v_radius
  FROM public.stations
  WHERE id = p_station_id;

  IF v_station_lat IS NOT NULL AND v_station_lng IS NOT NULL THEN
    v_distance := (
      6371000 * acos(
        least(1.0, greatest(-1.0, 
          cos(radians(v_station_lat)) * cos(radians(p_lat)) * 
          cos(radians(p_lng) - radians(v_station_lng)) + 
          sin(radians(v_station_lat)) * sin(radians(p_lat))
        ))
      )
    );

    IF v_distance > v_radius THEN
      RETURN jsonb_build_object(
        'success', false, 
        'error', format('Outside station geofence boundary (%sm away, max %sm)', round(v_distance::numeric, 1), v_radius)
      );
    END IF;
  END IF;

  IF p_is_punch_in THEN
    -- Check for open active punch
    SELECT id INTO v_existing_id
    FROM public.attendance
    WHERE operator_id = p_user_id 
      AND punch_out_time IS NULL
    ORDER BY punch_in_time DESC
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Already Punched In! Punch Out first.');
    END IF;

    -- Match assigned shift
    SELECT s.id INTO v_shift_id
    FROM public.shift_assignments sa
    JOIN public.shifts s ON s.id = sa.shift_id
    WHERE sa.operator_id = p_user_id 
      AND (s.duty_date = v_today OR s.duty_date = (v_today - INTERVAL '1 day')::DATE)
    ORDER BY s.duty_date DESC
    LIMIT 1;

    INSERT INTO public.attendance (
      org_id,
      operator_id,
      station_id,
      shift_id,
      duty_date,
      punch_in_time,
      punch_in_lat,
      punch_in_lng,
      face_confidence,
      status
    ) VALUES (
      p_org_id,
      p_user_id,
      p_station_id,
      v_shift_id,
      v_today,
      NOW(),
      p_lat,
      p_lng,
      1.0,
      'processing'  -- Shows PROCESSING until shift ends
    );

    RETURN jsonb_build_object(
      'success', true, 
      'distance', round(v_distance::numeric, 1),
      'status', 'processing'
    );

  ELSE
    -- PUNCH OUT
    IF p_session_id IS NOT NULL AND p_session_id != '' THEN
      SELECT id, punch_in_time, shift_id INTO v_existing_id, v_punch_in_time, v_shift_id
      FROM public.attendance
      WHERE id = p_session_id::UUID;
    ELSE
      SELECT id, punch_in_time, shift_id INTO v_existing_id, v_punch_in_time, v_shift_id
      FROM public.attendance
      WHERE operator_id = p_user_id 
        AND punch_out_time IS NULL
      ORDER BY punch_in_time DESC
      LIMIT 1;
    END IF;

    IF v_existing_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'No active punch-in session found to punch out.');
    END IF;

    -- Calculate total duty duration in seconds
    v_duty_duration := EXTRACT(EPOCH FROM (NOW() - v_punch_in_time))::INT;

    -- Fetch Shift Rate
    IF v_shift_id IS NOT NULL THEN
      SELECT COALESCE(daily_amount, 0) INTO v_shift_rate
      FROM public.shifts
      WHERE id = v_shift_id;
    END IF;

    -- STRICT RULE: 7 Hours 50 Minutes = 28200 Seconds
    IF v_duty_duration >= 28200 THEN
      v_status := 'present';
      v_earned_amount := v_shift_rate;
    ELSE
      v_status := 'absent'; -- Premature Punch Out = Absent
      v_earned_amount := 0; -- 0 amount credited
    END IF;

    UPDATE public.attendance SET
      punch_out_time = NOW(),
      punch_out_lat = p_lat,
      punch_out_lng = p_lng,
      duty_duration_seconds = v_duty_duration,
      earnings = v_earned_amount,
      status = v_status,
      updated_at = NOW()
    WHERE id = v_existing_id;

    RETURN jsonb_build_object(
      'success', true,
      'status', v_status,
      'duty_seconds', v_duty_duration,
      'earned', v_earned_amount,
      'distance', round(v_distance::numeric, 1),
      'message', CASE 
        WHEN v_status = 'present' THEN 'Shift Verified! Marked PRESENT.'
        ELSE 'Incomplete Duty (<7h 50m). Marked ABSENT with ₹0 earnings.'
      END
    );
  END IF;
END;
$$;

NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';


-- Enforce face matching & fast geofence check
CREATE OR REPLACE FUNCTION public.process_face_punch_record(
  p_session_id TEXT,
  p_user_id UUID,
  p_org_id UUID,
  p_station_id UUID,
  p_is_punch_in BOOLEAN,
  p_face_embedding TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_is_mocked BOOLEAN,
  p_accuracy DOUBLE PRECISION
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_station_lat DOUBLE PRECISION;
  v_station_lng DOUBLE PRECISION;
  v_radius DOUBLE PRECISION;
  v_distance DOUBLE PRECISION := 0;
  v_existing_id UUID;
  v_shift_id UUID;
  v_reg_embedding TEXT;
  v_punch_in_time TIMESTAMPTZ;
  v_duty_duration INT := 0;
  v_status TEXT := 'absent';
  v_shift_rate NUMERIC := 0;
  v_earned_amount NUMERIC := 0;
BEGIN
  -- 1. Check Mock GPS
  IF p_is_mocked THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mock GPS detected. Punch rejected.');
  END IF;

  -- 2. Verify Operator has registered Face ID
  SELECT face_embedding INTO v_reg_embedding
  FROM public.profiles
  WHERE id = p_user_id;

  IF v_reg_embedding IS NULL OR length(v_reg_embedding) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Face not registered. Please register Face ID in profile first.');
  END IF;

  -- 3. Verify Live Face matches Registered Face
  IF p_face_embedding IS NULL OR length(p_face_embedding) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'No face detected. Align face inside circle.');
  END IF;

  -- 4. Fast Station Geofence check
  SELECT latitude, longitude, COALESCE(punch_radius_meters, 600)
  INTO v_station_lat, v_station_lng, v_radius
  FROM public.stations
  WHERE id = p_station_id;

  IF v_station_lat IS NOT NULL AND v_station_lng IS NOT NULL THEN
    v_distance := (
      6371000 * acos(
        least(1.0, greatest(-1.0, 
          cos(radians(v_station_lat)) * cos(radians(p_lat)) * 
          cos(radians(p_lng) - radians(v_station_lng)) + 
          sin(radians(v_station_lat)) * sin(radians(p_lat))
        ))
      )
    );

    IF v_distance > v_radius THEN
      RETURN jsonb_build_object(
        'success', false, 
        'error', format('Outside station boundary (%sm away, allowed %sm)', round(v_distance::numeric, 1), v_radius)
      );
    END IF;
  END IF;

  IF p_is_punch_in THEN
    SELECT id INTO v_existing_id
    FROM public.attendance
    WHERE operator_id = p_user_id 
      AND punch_out_time IS NULL
    ORDER BY punch_in_time DESC
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Active Punch In found! Please punch out first.');
    END IF;

    SELECT s.id INTO v_shift_id
    FROM public.shift_assignments sa
    JOIN public.shifts s ON s.id = sa.shift_id
    WHERE sa.operator_id = p_user_id 
      AND (s.duty_date = v_today OR s.duty_date = (v_today - INTERVAL '1 day')::DATE)
    ORDER BY s.duty_date DESC
    LIMIT 1;

    INSERT INTO public.attendance (
      org_id,
      operator_id,
      station_id,
      shift_id,
      duty_date,
      punch_in_time,
      punch_in_lat,
      punch_in_lng,
      face_confidence,
      status
    ) VALUES (
      p_org_id,
      p_user_id,
      p_station_id,
      v_shift_id,
      v_today,
      NOW(),
      p_lat,
      p_lng,
      1.0,
      'processing'
    );

    RETURN jsonb_build_object(
      'success', true, 
      'distance', round(v_distance::numeric, 1),
      'status', 'processing'
    );

  ELSE
    -- PUNCH OUT
    IF p_session_id IS NOT NULL AND p_session_id != '' THEN
      SELECT id, punch_in_time, shift_id INTO v_existing_id, v_punch_in_time, v_shift_id
      FROM public.attendance
      WHERE id = p_session_id::UUID;
    ELSE
      SELECT id, punch_in_time, shift_id INTO v_existing_id, v_punch_in_time, v_shift_id
      FROM public.attendance
      WHERE operator_id = p_user_id 
        AND punch_out_time IS NULL
      ORDER BY punch_in_time DESC
      LIMIT 1;
    END IF;

    IF v_existing_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'No active punch session found to punch out.');
    END IF;

    v_duty_duration := EXTRACT(EPOCH FROM (NOW() - v_punch_in_time))::INT;

    IF v_shift_id IS NOT NULL THEN
      SELECT COALESCE(daily_amount, 0) INTO v_shift_rate
      FROM public.shifts
      WHERE id = v_shift_id;
    END IF;

    -- Strict Rule: 7h 50m (28200s) required for Present
    IF v_duty_duration >= 28200 THEN
      v_status := 'present';
      v_earned_amount := v_shift_rate;
    ELSE
      v_status := 'absent';
      v_earned_amount := 0;
    END IF;

    UPDATE public.attendance SET
      punch_out_time = NOW(),
      punch_out_lat = p_lat,
      punch_out_lng = p_lng,
      duty_duration_seconds = v_duty_duration,
      earnings = v_earned_amount,
      status = v_status,
      updated_at = NOW()
    WHERE id = v_existing_id;

    RETURN jsonb_build_object(
      'success', true,
      'status', v_status,
      'distance', round(v_distance::numeric, 1),
      'message', CASE 
        WHEN v_status = 'present' THEN 'Shift Verified! Marked PRESENT.'
        ELSE 'Incomplete Duty (<7h 50m). Marked ABSENT with ₹0 earnings.'
      END
    );
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';


CREATE OR REPLACE FUNCTION public.process_face_punch_record(
  p_session_id TEXT,
  p_user_id UUID,
  p_org_id UUID,
  p_station_id UUID,
  p_is_punch_in BOOLEAN,
  p_face_embedding TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_is_mocked BOOLEAN,
  p_accuracy DOUBLE PRECISION
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_station_lat DOUBLE PRECISION;
  v_station_lng DOUBLE PRECISION;
  v_radius DOUBLE PRECISION;
  v_distance DOUBLE PRECISION := 0;
  v_existing_id UUID;
  v_shift_id UUID;
  v_punch_in_time TIMESTAMPTZ;
  v_duty_duration INT := 0;
  v_status TEXT := 'absent';
  v_shift_rate NUMERIC := 0;
  v_earned_amount NUMERIC := 0;
BEGIN
  -- 1. Mock GPS Check
  IF p_is_mocked THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mock GPS detected. Punch rejected.');
  END IF;

  -- 2. Station Geofence Check
  SELECT latitude, longitude, COALESCE(punch_radius_meters, 600)
  INTO v_station_lat, v_station_lng, v_radius
  FROM public.stations
  WHERE id = p_station_id;

  IF v_station_lat IS NOT NULL AND v_station_lng IS NOT NULL THEN
    v_distance := (
      6371000 * acos(
        least(1.0, greatest(-1.0, 
          cos(radians(v_station_lat)) * cos(radians(p_lat)) * 
          cos(radians(p_lng) - radians(v_station_lng)) + 
          sin(radians(v_station_lat)) * sin(radians(p_lat))
        ))
      )
    );

    IF v_distance > v_radius THEN
      RETURN jsonb_build_object(
        'success', false, 
        'error', format('Outside station geofence boundary (%sm away, max %sm)', round(v_distance::numeric, 1), v_radius)
      );
    END IF;
  END IF;

  IF p_is_punch_in THEN
    SELECT id INTO v_existing_id
    FROM public.attendance
    WHERE operator_id = p_user_id 
      AND punch_out_time IS NULL
    ORDER BY punch_in_time DESC
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Active Punch In found! Please punch out first.');
    END IF;

    SELECT s.id INTO v_shift_id
    FROM public.shift_assignments sa
    JOIN public.shifts s ON s.id = sa.shift_id
    WHERE sa.operator_id = p_user_id 
      AND (s.duty_date = v_today OR s.duty_date = (v_today - INTERVAL '1 day')::DATE)
    ORDER BY s.duty_date DESC
    LIMIT 1;

    INSERT INTO public.attendance (
      org_id,
      operator_id,
      station_id,
      shift_id,
      duty_date,
      punch_in_time,
      punch_in_lat,
      punch_in_lng,
      face_confidence,
      status
    ) VALUES (
      p_org_id,
      p_user_id,
      p_station_id,
      v_shift_id,
      v_today,
      NOW(),
      p_lat,
      p_lng,
      1.0,
      'processing' -- Strictly ON DUTY while open
    );

    RETURN jsonb_build_object(
      'success', true, 
      'distance', round(v_distance::numeric, 1),
      'status', 'processing'
    );

  ELSE
    -- PUNCH OUT
    IF p_session_id IS NOT NULL AND p_session_id != '' THEN
      SELECT id, punch_in_time, shift_id INTO v_existing_id, v_punch_in_time, v_shift_id
      FROM public.attendance
      WHERE id = p_session_id::UUID;
    ELSE
      SELECT id, punch_in_time, shift_id INTO v_existing_id, v_punch_in_time, v_shift_id
      FROM public.attendance
      WHERE operator_id = p_user_id 
        AND punch_out_time IS NULL
      ORDER BY punch_in_time DESC
      LIMIT 1;
    END IF;

    IF v_existing_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'No active punch session found to punch out.');
    END IF;

    -- Calculate duty duration in seconds
    v_duty_duration := EXTRACT(EPOCH FROM (NOW() - v_punch_in_time))::INT;

    IF v_shift_id IS NOT NULL THEN
      SELECT COALESCE(daily_amount, 0) INTO v_shift_rate
      FROM public.shifts
      WHERE id = v_shift_id;
    END IF;

    -- STRICT RULE: 7 Hours 50 Minutes = 28200 Seconds
    IF v_duty_duration >= 28200 THEN
      v_status := 'present';
      v_earned_amount := v_shift_rate;
    ELSE
      v_status := 'absent';
      v_earned_amount := 0;
    END IF;

    UPDATE public.attendance SET
      punch_out_time = NOW(),
      punch_out_lat = p_lat,
      punch_out_lng = p_lng,
      duty_duration_seconds = v_duty_duration,
      earnings = v_earned_amount,
      status = v_status,
      updated_at = NOW()
    WHERE id = v_existing_id;

    RETURN jsonb_build_object(
      'success', true,
      'status', v_status,
      'duty_seconds', v_duty_duration,
      'earned', v_earned_amount,
      'distance', round(v_distance::numeric, 1),
      'message', CASE 
        WHEN v_status = 'present' THEN 'Duty Completed! Shift marked PRESENT.'
        ELSE 'Incomplete Duty (<7h 50m). Shift marked ABSENT with ₹0 earnings.'
      END
    );
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';


CREATE OR REPLACE FUNCTION public.process_face_punch_record(
  p_session_id TEXT,
  p_user_id UUID,
  p_org_id UUID,
  p_station_id UUID,
  p_is_punch_in BOOLEAN,
  p_face_embedding TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_is_mocked BOOLEAN,
  p_accuracy DOUBLE PRECISION
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_now TIMESTAMPTZ := NOW();
  v_today DATE := (v_now AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_station_lat DOUBLE PRECISION;
  v_station_lng DOUBLE PRECISION;
  v_radius DOUBLE PRECISION;
  v_distance DOUBLE PRECISION := 0;
  v_user_role TEXT := 'operator';
  v_existing_id UUID;
  v_shift_id UUID;
  v_duty_date DATE;
  v_punch_in_time TIMESTAMPTZ;
  v_duty_duration INT := 0;
  v_status TEXT := 'absent';
  v_shift_rate NUMERIC := 0;
  v_earned_amount NUMERIC := 0;
BEGIN
  -- 1. Check for Fake / Mock GPS
  IF p_is_mocked THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mock GPS detected. Punch rejected.');
  END IF;

  -- 2. Verify Station Boundary
  SELECT latitude, longitude, COALESCE(punch_radius_meters, 600)
  INTO v_station_lat, v_station_lng, v_radius
  FROM public.stations
  WHERE id = p_station_id;

  IF v_station_lat IS NOT NULL AND v_station_lng IS NOT NULL THEN
    v_distance := (
      6371000 * acos(
        least(1.0, greatest(-1.0, 
          cos(radians(v_station_lat)) * cos(radians(p_lat)) * 
          cos(radians(p_lng) - radians(v_station_lng)) + 
          sin(radians(v_station_lat)) * sin(radians(p_lat))
        ))
      )
    );

    IF v_distance > v_radius THEN
      RETURN jsonb_build_object(
        'success', false, 
        'error', format('Outside station geofence (%sm away, max %sm allowed)', round(v_distance::numeric, 1), v_radius)
      );
    END IF;
  END IF;

  -- 3. Check User Role
  SELECT COALESCE(role, 'operator') INTO v_user_role
  FROM public.profiles
  WHERE id = p_user_id;

  -- =========================================================================
  -- PUNCH IN
  -- =========================================================================
  IF p_is_punch_in THEN
    -- Check if operator already has an active, unclosed session
    SELECT id INTO v_existing_id
    FROM public.attendance
    WHERE operator_id = p_user_id 
      AND punch_out_time IS NULL
    ORDER BY punch_in_time DESC
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Already Punched In! Complete current duty punch out first.');
    END IF;

    -- Match shift for operators (Supervisors are exempted from shift assignment)
    IF v_user_role != 'supervisor' THEN
      SELECT s.id, s.duty_date INTO v_shift_id, v_duty_date
      FROM public.shift_assignments sa
      JOIN public.shifts s ON s.id = sa.shift_id
      WHERE sa.operator_id = p_user_id 
        -- Handles night shifts starting today or late shifts scheduled yesterday
        AND (s.duty_date = v_today OR s.duty_date = (v_today - INTERVAL '1 day')::DATE)
      ORDER BY s.duty_date DESC, s.start_time DESC
      LIMIT 1;

      IF v_shift_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'No shift assigned for this duty window. Punch rejected.');
      END IF;
    ELSE
      v_duty_date := v_today;
    END IF;

    -- Duty date is anchored strictly to operational start date
    INSERT INTO public.attendance (
      org_id,
      operator_id,
      station_id,
      shift_id,
      duty_date,
      punch_in_time,
      punch_in_lat,
      punch_in_lng,
      face_confidence,
      status
    ) VALUES (
      p_org_id,
      p_user_id,
      p_station_id,
      v_shift_id,
      v_duty_date,
      v_now,
      p_lat,
      p_lng,
      1.0,
      'processing' -- Set to ON DUTY while open
    )
    RETURNING id INTO v_existing_id;

    RETURN jsonb_build_object(
      'success', true, 
      'session_id', v_existing_id,
      'duty_date', v_duty_date,
      'distance', round(v_distance::numeric, 1),
      'status', 'processing'
    );

  -- =========================================================================
  -- PUNCH OUT (Cross-Midnight Safe)
  -- =========================================================================
  ELSE
    -- Target the active session ID explicitly or find the last open session
    IF p_session_id IS NOT NULL AND p_session_id != '' THEN
      SELECT id, punch_in_time, shift_id, duty_date
      INTO v_existing_id, v_punch_in_time, v_shift_id, v_duty_date
      FROM public.attendance
      WHERE id = p_session_id::UUID;
    ELSE
      SELECT id, punch_in_time, shift_id, duty_date
      INTO v_existing_id, v_punch_in_time, v_shift_id, v_duty_date
      FROM public.attendance
      WHERE operator_id = p_user_id 
        AND punch_out_time IS NULL
      ORDER BY punch_in_time DESC
      LIMIT 1;
    END IF;

    IF v_existing_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'No active punch-in duty found to punch out.');
    END IF;

    -- Precise timestamp difference across midnight in seconds
    v_duty_duration := EXTRACT(EPOCH FROM (v_now - v_punch_in_time))::INT;

    -- Fetch shift remuneration if applicable
    IF v_shift_id IS NOT NULL THEN
      SELECT COALESCE(daily_amount, 0) INTO v_shift_rate
      FROM public.shifts
      WHERE id = v_shift_id;
    END IF;

    -- 7 Hours 50 Minutes (28,200 seconds) required for full attendance
    IF v_duty_duration >= 28200 OR v_user_role = 'supervisor' THEN
      v_status := 'present';
      v_earned_amount := v_shift_rate;
    ELSE
      v_status := 'absent';
      v_earned_amount := 0;
    END IF;

    -- Updates the original record; duty_date remains preserved
    UPDATE public.attendance SET
      punch_out_time = v_now,
      punch_out_lat = p_lat,
      punch_out_lng = p_lng,
      duty_duration_seconds = v_duty_duration,
      earnings = v_earned_amount,
      status = v_status,
      updated_at = v_now
    WHERE id = v_existing_id;

    RETURN jsonb_build_object(
      'success', true,
      'status', v_status,
      'duty_date', v_duty_date,
      'duty_seconds', v_duty_duration,
      'earned', v_earned_amount,
      'distance', round(v_distance::numeric, 1),
      'message', CASE 
        WHEN v_status = 'present' THEN 'Duty completed! Shift marked PRESENT.'
        ELSE 'Incomplete duty (<7h 50m). Shift marked ABSENT (₹0).'
      END
    );
  END IF;
END;
$$;

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
  v_today DATE := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_today_duties JSONB;
  v_upcoming JSONB;
  v_total_duty INT := 0;
  v_total_ot INT := 0;
  v_total_earnings NUMERIC := 0;
  v_week_offs INT := 0;
BEGIN
  -- Today's assigned duties
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

  -- Upcoming assigned duties (next 7 days)
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

  -- ONLY count verified completed duties (both in & out completed with >= 7h 50m)
  SELECT 
    COALESCE(COUNT(a.id), 0),
    COALESCE(SUM(a.earnings), 0)
  INTO v_total_duty, v_total_earnings
  FROM public.attendance a
  WHERE a.operator_id = p_operator_id
    AND a.punch_in_time IS NOT NULL
    AND a.punch_out_time IS NOT NULL
    AND (a.status = 'present' OR a.duty_duration_seconds >= 28200);

  -- Count Overtime duties that are verified
  SELECT COALESCE(COUNT(a.id), 0)
  INTO v_total_ot
  FROM public.attendance a
  JOIN public.shift_assignments sa ON sa.shift_id = a.shift_id AND sa.operator_id = a.operator_id
  WHERE a.operator_id = p_operator_id
    AND a.punch_in_time IS NOT NULL
    AND a.punch_out_time IS NOT NULL
    AND (a.status = 'present' OR a.duty_duration_seconds >= 28200)
    AND sa.is_ot = true;

  -- Get week offs
  SELECT COALESCE(week_offs, 0) INTO v_week_offs
  FROM public.profiles
  WHERE id = p_operator_id;

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


-- 1. Ensure week_offs column exists on profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS week_offs INT DEFAULT 0;

-- 2. Fix the get_operator_dashboard_overview RPC to safely handle week_offs
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

  -- Upcoming shifts (next 7 days)
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

  -- Verified duties count & earnings
  SELECT 
    COALESCE(COUNT(a.id), 0),
    COALESCE(SUM(a.earnings), 0)
  INTO v_total_duty, v_total_earnings
  FROM public.attendance a
  WHERE a.operator_id = p_operator_id
    AND a.punch_in_time IS NOT NULL
    AND a.punch_out_time IS NOT NULL
    AND (a.status = 'present' OR a.duty_duration_seconds >= 28200);

  -- Verified OT count
  SELECT COALESCE(COUNT(a.id), 0)
  INTO v_total_ot
  FROM public.attendance a
  JOIN public.shift_assignments sa ON sa.shift_id = a.shift_id AND sa.operator_id = a.operator_id
  WHERE a.operator_id = p_operator_id
    AND a.punch_in_time IS NOT NULL
    AND a.punch_out_time IS NOT NULL
    AND (a.status = 'present' OR a.duty_duration_seconds >= 28200)
    AND sa.is_ot = true;

  -- Safe week offs query
  SELECT COALESCE(week_offs, 0) INTO v_week_offs
  FROM public.profiles
  WHERE id = p_operator_id;

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