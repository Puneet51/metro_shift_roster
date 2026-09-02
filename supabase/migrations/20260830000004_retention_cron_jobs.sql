-- Enable pg_cron for scheduled background maintenance
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- 1. FORGOTTEN PUNCH-OUT CLEANUP FUNCTION (>10 Hours)
CREATE OR REPLACE FUNCTION handle_forgotten_punch_outs()
RETURNS void AS $$
BEGIN
    -- Update open sessions past 10 hours to auto_absent
    WITH expired_sessions AS (
        UPDATE punch_sessions
        SET status = 'auto_absent',
            updated_at = NOW()
        WHERE punch_out_at IS NULL
          AND punch_in_at < (NOW() - INTERVAL '10 hours')
          AND status = 'in_progress'
        RETURNING id, org_id, operator_id, station_id, shift_id, duty_date
    )
    -- Record as absent in attendance table
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
    )
    SELECT 
        org_id,
        operator_id,
        station_id,
        shift_id,
        id,
        duty_date,
        'absent',
        FALSE,
        0.00
    FROM expired_sessions;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. DATA RETENTION POLICY ENFORCEMENT FUNCTION
CREATE OR REPLACE FUNCTION purge_expired_records()
RETURNS void AS $$
BEGIN
    -- Delete shifts completed more than 1 week ago (7 days)
    DELETE FROM shifts
    WHERE duty_date < (CURRENT_DATE - INTERVAL '7 days')
      AND is_published = TRUE;

    -- Delete attendance records older than 2 months (60 days)
    DELETE FROM attendance
    WHERE duty_date < (CURRENT_DATE - INTERVAL '60 days');

    -- Delete audit logs older than 90 days
    DELETE FROM audit_logs
    WHERE created_at < (NOW() - INTERVAL '90 days');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. SCHEDULE CRON JOBS
-- Run forgotten punch check every 15 minutes
SELECT cron.schedule(
    'check_forgotten_punches',
    '*/15 * * * *',
    'SELECT handle_forgotten_punch_outs();'
);

-- Run retention data purge every night at 02:00 AM
SELECT cron.schedule(
    'purge_old_records_daily',
    '0 2 * * *',
    'SELECT purge_expired_records();'
);