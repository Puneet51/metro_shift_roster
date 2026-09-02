-- 1. HELPER FUNCTIONS FOR RLS EVALUATION
CREATE OR REPLACE FUNCTION get_current_user_role()
RETURNS user_role AS $$
  SELECT role FROM profiles WHERE id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_current_user_org_id()
RETURNS UUID AS $$
  SELECT org_id FROM profiles WHERE id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 2. ENABLE ROW LEVEL SECURITY ON ALL TABLES
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE stations ENABLE ROW LEVEL SECURITY;
ALTER TABLE station_operating_systems ENABLE ROW LEVEL SECURITY;
ALTER TABLE shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE shift_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE punch_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- 3. PROFILES POLICIES
-- Platform Admin has full access
CREATE POLICY admin_all_profiles ON profiles
  FOR ALL USING (get_current_user_role() = 'admin');

-- Supervisor can read & create/edit profiles within their organization
CREATE POLICY supervisor_manage_org_profiles ON profiles
  FOR ALL USING (
    get_current_user_role() = 'supervisor' 
    AND org_id = get_current_user_org_id()
  );

-- Operator can view teammates in same org and edit own profile
CREATE POLICY operator_view_org_profiles ON profiles
  FOR SELECT USING (org_id = get_current_user_org_id());

CREATE POLICY operator_update_own_profile ON profiles
  FOR UPDATE USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- 4. STATIONS & OPERATING SYSTEMS POLICIES
CREATE POLICY admin_all_stations ON stations
  FOR ALL USING (get_current_user_role() = 'admin');

CREATE POLICY supervisor_manage_stations ON stations
  FOR ALL USING (
    get_current_user_role() = 'supervisor' 
    AND org_id = get_current_user_org_id()
  );

CREATE POLICY operator_view_stations ON stations
  FOR SELECT USING (org_id = get_current_user_org_id());

CREATE POLICY supervisor_manage_station_systems ON station_operating_systems
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM stations 
      WHERE stations.id = station_operating_systems.station_id 
      AND stations.org_id = get_current_user_org_id()
    )
  );

CREATE POLICY operator_view_station_systems ON station_operating_systems
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM stations 
      WHERE stations.id = station_operating_systems.station_id 
      AND stations.org_id = get_current_user_org_id()
    )
  );

-- 5. SHIFTS & ASSIGNMENTS POLICIES
CREATE POLICY supervisor_manage_shifts ON shifts
  FOR ALL USING (
    get_current_user_role() = 'supervisor' 
    AND org_id = get_current_user_org_id()
  );

CREATE POLICY operator_view_shifts ON shifts
  FOR SELECT USING (
    org_id = get_current_user_org_id() 
    AND is_published = TRUE
  );

CREATE POLICY supervisor_manage_assignments ON shift_assignments
  FOR ALL USING (
    get_current_user_role() = 'supervisor' 
    AND org_id = get_current_user_org_id()
  );

CREATE POLICY operator_view_own_assignments ON shift_assignments
  FOR SELECT USING (
    org_id = get_current_user_org_id() 
    AND operator_id = auth.uid()
  );

-- 6. PUNCH SESSIONS & ATTENDANCE POLICIES
CREATE POLICY operator_manage_own_punches ON punch_sessions
  FOR ALL USING (operator_id = auth.uid());

CREATE POLICY supervisor_manage_org_punches ON punch_sessions
  FOR ALL USING (
    get_current_user_role() = 'supervisor' 
    AND org_id = get_current_user_org_id()
  );

CREATE POLICY operator_view_own_attendance ON attendance
  FOR SELECT USING (operator_id = auth.uid());

CREATE POLICY supervisor_manage_org_attendance ON attendance
  FOR ALL USING (
    get_current_user_role() = 'supervisor' 
    AND org_id = get_current_user_org_id()
  );

-- 7. NOTIFICATIONS & DEVICE TOKENS POLICIES
CREATE POLICY user_manage_own_tokens ON device_tokens
  FOR ALL USING (user_id = auth.uid());

CREATE POLICY user_view_own_notifications ON notifications
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY user_update_own_notifications ON notifications
  FOR UPDATE USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- 8. APP VERSIONS (PUBLIC READ FOR UPDATE ENFORCEMENT)
CREATE POLICY public_read_app_versions ON app_versions
  FOR SELECT USING (TRUE);

CREATE POLICY admin_manage_app_versions ON app_versions
  FOR ALL USING (get_current_user_role() = 'admin');