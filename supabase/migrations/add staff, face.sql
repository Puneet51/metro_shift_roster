-- 1. Add shift definitions and timing fields to stations
ALTER TABLE stations 
ADD COLUMN IF NOT EXISTS default_shift_name VARCHAR(100) DEFAULT 'A Shift',
ADD COLUMN IF NOT EXISTS default_start_time TIME DEFAULT '06:00:00',
ADD COLUMN IF NOT EXISTS default_end_time TIME DEFAULT '14:00:00';

-- 2. Add Face Registration and Face Embedding storage in profiles
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS is_face_registered BOOLEAN DEFAULT FALSE;

-- 3. Secure RPC to register Face Biometrics
CREATE OR REPLACE FUNCTION register_user_face(p_user_id UUID, p_embedding JSONB)
RETURNS void AS $$
BEGIN
  UPDATE profiles
  SET face_embedding = p_embedding,
      is_face_registered = TRUE,
      updated_at = NOW()
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Secure RPC to fetch registered operators within tenant org
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
    WHERE org_id = p_org_id 
      AND role = 'tom_operator'
      AND is_active = TRUE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;