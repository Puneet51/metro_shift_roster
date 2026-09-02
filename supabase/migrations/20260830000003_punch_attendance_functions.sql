-- 1. PUNCH IN FUNCTION
CREATE OR REPLACE FUNCTION process_punch_in(
    p_station_id UUID,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_is_face_verified BOOLEAN
)
RETURNS JSONB AS $$
DECLARE
    v_operator_id UUID := auth.uid();
    v_org_id UUID;
    v_station stations%ROWTYPE;
    v_distance DOUBLE PRECISION;
    v_assigned_shift_id UUID;
    v_duty_date DATE := CURRENT_DATE;
    v_last_punch_out TIMESTAMPTZ;
    v_session_id UUID;
    v_status punch_status := 'in_progress';
BEGIN
    -- Verify face validation
    IF NOT p_is_face_verified THEN
        RAISE EXCEPTION 'Face verification failed or is incomplete.';
    END IF;

    -- Get operator organization
    SELECT org_id INTO v_org_id FROM profiles WHERE id = v_operator_id;
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'Operator profile not found or inactive.';
    END IF;

    -- Verify station & compute geo-distance in meters
    SELECT * INTO v_station FROM stations WHERE id = p_station_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Station not found.';
    END IF;

    v_distance := ST_Distance(
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(v_station.longitude, v_station.latitude), 4326)::geography
    );

    IF v_distance > v_station.punch_radius_meters THEN
        RAISE EXCEPTION 'You are outside the permitted station radius (% meters away, allowed %m).', 
            ROUND(v_distance::numeric, 1), v_station.punch_radius_meters;
    END IF;

    -- Check 1-Hour cooldown from last punch-out
    SELECT punch_out_at INTO v_last_punch_out 
    FROM punch_sessions 
    WHERE operator_id = v_operator_id 
    ORDER BY punch_out_at DESC NULLS LAST 
    LIMIT 1;

    IF v_last_punch_out IS NOT NULL AND (NOW() - v_last_punch_out) < INTERVAL '1 hour' THEN
        RAISE EXCEPTION 'Re-punch not allowed within 1 hour of previous punch out.';
    END IF;

    -- Check if active session already exists
    IF EXISTS (
        SELECT 1 FROM punch_sessions 
        WHERE operator_id = v_operator_id AND punch_out_at IS NULL
    ) THEN
        RAISE EXCEPTION 'You already have an active punch-in session.';
    END IF;

    -- Find matching published shift assignment for current date/time
    SELECT s.id INTO v_assigned_shift_id
    FROM shifts s
    JOIN shift_assignments sa ON sa.shift_id = s.id
    WHERE sa.operator_id = v_operator_id
      AND s.station_id = p_station_id
      AND s.duty_date = v_duty_date
      AND s.is_published = TRUE
    LIMIT 1;

    -- If no shift is assigned, set status to pending supervisor approval
    IF v_assigned_shift_id IS NULL THEN
        v_status := 'unassigned_pending';
    END IF;

    -- Create Punch Session (Duty date anchored to punch-in timestamp)
    INSERT INTO punch_sessions (
        org_id,
        operator_id,
        station_id,
        shift_id,
        duty_date,
        punch_in_at,
        punch_in_lat,
        punch_in_lng,
        punch_in_verified,
        status
    ) VALUES (
        v_org_id,
        v_operator_id,
        p_station_id,
        v_assigned_shift_id,
        v_duty_date,
        NOW(),
        p_lat,
        p_lng,
        p_is_face_verified,
        v_status
    ) RETURNING id INTO v_session_id;

    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'status', v_status,
        'duty_date', v_duty_date,
        'assigned', (v_assigned_shift_id IS NOT NULL)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. PUNCH OUT FUNCTION
CREATE OR REPLACE FUNCTION process_punch_out(
    p_session_id UUID,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_is_face_verified BOOLEAN
)
RETURNS JSONB AS $$
DECLARE
    v_session punch_sessions%ROWTYPE;
    v_station stations%ROWTYPE;
    v_distance DOUBLE PRECISION;
    v_duty_seconds NUMERIC;
    v_fixed_amount NUMERIC(10, 2);
    v_is_ot BOOLEAN := FALSE;
BEGIN
    IF NOT p_is_face_verified THEN
        RAISE EXCEPTION 'Face verification failed or is incomplete.';
    END IF;

    SELECT * INTO v_session 
    FROM punch_sessions 
    WHERE id = p_session_id AND operator_id = auth.uid();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active punch session not found.';
    END IF;

    IF v_session.punch_out_at IS NOT NULL THEN
        RAISE EXCEPTION 'Punch out already recorded for this session.';
    END IF;

    -- Validate punch out geofence
    SELECT * INTO v_station FROM stations WHERE id = v_session.station_id;
    v_distance := ST_Distance(
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(v_station.longitude, v_station.latitude), 4326)::geography
    );

    IF v_distance > v_station.punch_radius_meters THEN
        RAISE EXCEPTION 'You are outside the permitted station radius for punch out.';
    END IF;

    -- Calculate duration: 8 hours = 28800s. With 10 min early grace = 28200s (7h 50m)
    v_duty_seconds := EXTRACT(EPOCH FROM (NOW() - v_session.punch_in_at));

    IF v_duty_seconds < 28200 THEN
        RAISE EXCEPTION 'Early punch out not permitted. 8 hours duty mandatory (10 min early completion allowed).';
    END IF;

    -- Get shift/station fixed earnings
    IF v_session.shift_id IS NOT NULL THEN
        SELECT daily_amount INTO v_fixed_amount FROM shifts WHERE id = v_session.shift_id;
        SELECT is_ot INTO v_is_ot FROM shift_assignments WHERE shift_id = v_session.shift_id AND operator_id = auth.uid();
    ELSE
        SELECT default_fixed_amount INTO v_fixed_amount FROM stations WHERE id = v_session.station_id;
    END IF;

    -- Update Punch Session
    UPDATE punch_sessions
    SET punch_out_at = NOW(),
        punch_out_lat = p_lat,
        punch_out_lng = p_lng,
        punch_out_verified = p_is_face_verified,
        status = CASE WHEN v_session.status = 'unassigned_pending' THEN 'unassigned_pending' ELSE 'completed' END,
        updated_at = NOW()
    WHERE id = p_session_id;

    -- If assigned duty, record finalized attendance immediately
    IF v_session.status = 'in_progress' THEN
        INSERT INTO attendance (
            org_id,
            operator_id,
            station_id,
            shift_id,
            punch_session_id,
            duty_date,
            status,
            is_ot,
            earnings
        ) VALUES (
            v_session.org_id,
            v_session.operator_id,
            v_session.station_id,
            v_session.shift_id,
            v_session.id,
            v_session.duty_date, -- Cross-midnight preserved
            'present',
            COALESCE(v_is_ot, FALSE),
            COALESCE(v_fixed_amount, 700.00)
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'duty_date', v_session.duty_date,
        'completed', (v_session.status = 'in_progress')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;