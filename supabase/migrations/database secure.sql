-- 1. Create the App Version Table & RPC Function first
CREATE TABLE IF NOT EXISTS public.app_versions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  platform VARCHAR(20) NOT NULL UNIQUE,
  latest_version VARCHAR(20) NOT NULL,
  min_required_version VARCHAR(20) NOT NULL,
  update_url TEXT NOT NULL,
  release_notes TEXT,
  force_update BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION public.set_app_version_config(
  p_platform VARCHAR,
  p_latest_version VARCHAR,
  p_min_version VARCHAR,
  p_update_url TEXT,
  p_release_notes TEXT,
  p_force_update BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.app_versions (
    platform,
    latest_version,
    min_required_version,
    update_url,
    release_notes,
    force_update,
    updated_at
  ) VALUES (
    p_platform,
    p_latest_version,
    p_min_version,
    p_update_url,
    p_release_notes,
    p_force_update,
    NOW()
  )
  ON CONFLICT (platform) DO UPDATE SET
    latest_version = EXCLUDED.latest_version,
    min_required_version = EXCLUDED.min_required_version,
    update_url = EXCLUDED.update_url,
    release_notes = EXCLUDED.release_notes,
    force_update = EXCLUDED.force_update,
    updated_at = NOW();

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 2. Revoke Dangerous / Public RPC Permissions
REVOKE EXECUTE ON FUNCTION public.admin_transfer_supervisor_data(UUID, UUID, UUID) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.get_org_supervisors(UUID) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.get_org_supervisors_overview(UUID) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.set_app_version_config(VARCHAR, VARCHAR, VARCHAR, TEXT, TEXT, BOOLEAN) FROM anon, public;

-- Grant execution to authenticated users
GRANT EXECUTE ON FUNCTION public.admin_transfer_supervisor_data(UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_org_supervisors(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_org_supervisors_overview(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_app_version_config(VARCHAR, VARCHAR, VARCHAR, TEXT, TEXT, BOOLEAN) TO authenticated;

-- 3. Row Level Security Policies
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "profiles_tenant_select" ON public.profiles;
DROP POLICY IF EXISTS "profiles_self_update" ON public.profiles;

CREATE POLICY "profiles_tenant_select"
ON public.profiles FOR SELECT
TO authenticated, anon
USING (is_active = TRUE);

CREATE POLICY "profiles_self_update"
ON public.profiles FOR UPDATE
TO authenticated, anon
USING (TRUE)
WITH CHECK (role = 'tom_operator' OR role = 'supervisor');

ALTER TABLE public.stations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "stations_tenant_select" ON public.stations;
DROP POLICY IF EXISTS "stations_write_policy" ON public.stations;

CREATE POLICY "stations_tenant_select"
ON public.stations FOR SELECT
TO authenticated, anon
USING (TRUE);

CREATE POLICY "stations_write_policy"
ON public.stations FOR ALL
TO authenticated
USING (TRUE)
WITH CHECK (TRUE);

ALTER TABLE public.punch_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "punch_sessions_read" ON public.punch_sessions;
DROP POLICY IF EXISTS "attendance_read" ON public.attendance;

CREATE POLICY "punch_sessions_read"
ON public.punch_sessions FOR SELECT
TO authenticated, anon
USING (TRUE);

CREATE POLICY "attendance_read"
ON public.attendance FOR SELECT
TO authenticated, anon
USING (TRUE);

-- 4. Geofenced Anti-Spoofing Biometric Punch Function
CREATE OR REPLACE FUNCTION public.process_face_punch_record(
  p_session_id UUID,
  p_user_id UUID,
  p_org_id UUID,
  p_station_id UUID,
  p_is_punch_in BOOLEAN,
  p_face_embedding JSONB,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_is_mocked BOOLEAN DEFAULT FALSE,
  p_accuracy DOUBLE PRECISION DEFAULT 100.0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_verify JSONB;
  v_station public.stations%ROWTYPE;
  v_session_id UUID;
  v_distance DOUBLE PRECISION;
  v_allowed_radius DOUBLE PRECISION;
  v_fixed_amount NUMERIC(10,2);
BEGIN
  -- Anti-Mock / Fake GPS Gate
  IF p_is_mocked IS TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Security Alert: Mock / Simulated GPS detected. Punch rejected.');
  END IF;

  -- Accuracy Gate (> 80m rejected)
  IF p_accuracy > 80.0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'GPS accuracy too low (' || ROUND(p_accuracy::NUMERIC, 1) || 'm). Move outdoors or enable High Accuracy Location.');
  END IF;

  -- Biometric Verification
  v_verify := public.verify_registered_face_embedding(p_user_id, p_face_embedding);
  IF (v_verify ->> 'success')::BOOLEAN IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', v_verify ->> 'error');
  END IF;

  IF (v_verify ->> 'matched')::BOOLEAN IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false, 
      'error', 'Face match failed. Registered profile did not match (Similarity: ' || ROUND((v_verify ->> 'similarity')::NUMERIC, 2) || ')'
    );
  END IF;

  -- Station Distance Verification
  SELECT * INTO v_station FROM public.stations WHERE id = p_station_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Target metro station not found.');
  END IF;

  v_distance := 6371000 * 2 * ASIN(SQRT(
    POWER(SIN(RADIANS(v_station.latitude - p_lat) / 2), 2) +
    COS(RADIANS(p_lat)) * COS(RADIANS(v_station.latitude)) *
    POWER(SIN(RADIANS(v_station.longitude - p_lng) / 2), 2)
  ));

  v_allowed_radius := COALESCE(v_station.punch_radius_meters, 100);

  IF v_distance > v_allowed_radius THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Outside Geofence: You are ' || ROUND(v_distance::NUMERIC, 1) || 'm away from ' || v_station.name || ' (Allowed: ' || v_allowed_radius || 'm).'
    );
  END IF;

  v_fixed_amount := COALESCE(v_station.default_fixed_amount, 700.00);

  IF p_is_punch_in THEN
    IF EXISTS (
      SELECT 1 FROM public.punch_sessions 
      WHERE operator_id = p_user_id AND punch_out_at IS NULL AND duty_date = CURRENT_DATE
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'You already have an active ongoing shift session.');
    END IF;

    INSERT INTO public.punch_sessions (
      org_id, operator_id, station_id, duty_date, punch_in_at, punch_in_lat, punch_in_lng, punch_in_verified, status
    ) VALUES (
      p_org_id, p_user_id, p_station_id, CURRENT_DATE, NOW(), p_lat, p_lng, TRUE, 'in_progress'
    ) RETURNING id INTO v_session_id;

    RETURN jsonb_build_object('success', true, 'session_id', v_session_id, 'action', 'PUNCH_IN', 'distance', ROUND(v_distance::NUMERIC, 1));
  ELSE
    UPDATE public.punch_sessions
    SET punch_out_at = NOW(),
        punch_out_lat = p_lat,
        punch_out_lng = p_lng,
        punch_out_verified = TRUE,
        status = 'completed',
        updated_at = NOW()
    WHERE id = p_session_id AND operator_id = p_user_id;

    INSERT INTO public.attendance (
      org_id, operator_id, station_id, duty_date, status, is_ot, earnings
    ) VALUES (
      p_org_id, p_user_id, p_station_id, CURRENT_DATE, 'present', FALSE, v_fixed_amount
    )
    ON CONFLICT (operator_id, duty_date)
    DO UPDATE SET status = 'present', earnings = v_fixed_amount;

    RETURN jsonb_build_object('success', true, 'action', 'PUNCH_OUT', 'distance', ROUND(v_distance::NUMERIC, 1));
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_face_punch_record(UUID, UUID, UUID, UUID, BOOLEAN, JSONB, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN, DOUBLE PRECISION) TO anon, authenticated, service_role;