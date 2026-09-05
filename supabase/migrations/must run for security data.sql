-- 1. Helper function that bypasses RLS safely to check user role
CREATE OR REPLACE FUNCTION auth_user_role(p_user_id UUID)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT role FROM profiles WHERE id = p_user_id LIMIT 1;
$$;

-- 2. Helper function to check effective supervisor ID
CREATE OR REPLACE FUNCTION auth_effective_supervisor(p_user_id UUID)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT 
    CASE 
      WHEN is_reliever = TRUE AND parent_supervisor_id IS NOT NULL 
        THEN parent_supervisor_id 
      ELSE id 
    END
  FROM profiles 
  WHERE id = p_user_id 
  LIMIT 1;
$$;

-- 3. Replace the open SELECT policy with a hardened policy
DROP POLICY IF EXISTS "profiles_select_policy" ON profiles;

CREATE POLICY "profiles_select_policy"
ON profiles
FOR SELECT
TO authenticated, anon
USING (
  -- Anyone can read basic profile info needed to verify their own phone during login
  phone_number = current_setting('request.headers', true)::json->>'x-phone-number'
  OR
  -- Admins can select everything
  auth_user_role(auth.uid()) = 'admin'
  OR
  -- Supervisors & Admins profiles are visible for directory/assignment
  role IN ('supervisor', 'admin')
  OR
  -- OPERATORS CAN ONLY BE SEEN BY THEIR ASSIGNED SUPERVISOR / RELIEVER
  (
    role = 'tom_operator'
    AND parent_supervisor_id = auth_effective_supervisor(auth.uid())
  )
);