-- 1. Remove the strict foreign key on profiles.id
ALTER TABLE profiles 
DROP CONSTRAINT IF EXISTS profiles_id_fkey;

-- 2. Make id default to a generated UUID
ALTER TABLE profiles 
ALTER COLUMN id SET DEFAULT uuid_generate_v4();

-- 3. Add an explicit INSERT policy for Admins and Supervisors
CREATE POLICY admin_insert_profiles ON profiles
  FOR INSERT WITH CHECK (get_current_user_role() = 'admin');

CREATE POLICY supervisor_insert_profiles ON profiles
  FOR INSERT WITH CHECK (
    get_current_user_role() = 'supervisor' 
    AND org_id = get_current_user_org_id()
  );