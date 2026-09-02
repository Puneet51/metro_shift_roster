-- 1. Ensure reliever link columns exist on profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_reliever BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS parent_supervisor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- 2. Create promotion & phone handover function
CREATE OR REPLACE FUNCTION public.promote_reliever_to_primary(
  p_reliever_id UUID,
  p_new_phone TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_parent_id UUID;
BEGIN
  -- Get parent supervisor
  SELECT parent_supervisor_id INTO v_parent_id
  FROM public.profiles
  WHERE id = p_reliever_id;

  -- 1. Demote or deactivate old parent supervisor if needed
  IF v_parent_id IS NOT NULL THEN
    UPDATE public.profiles
    SET is_active = false
    WHERE id = v_parent_id;
  END IF;

  -- 2. Promote reliever to primary supervisor
  UPDATE public.profiles
  SET 
    is_reliever = false,
    parent_supervisor_id = NULL,
    is_active = true,
    phone_number = COALESCE(NULLIF(p_new_phone, ''), phone_number)
  WHERE id = p_reliever_id;
END;
$$;

NOTIFY pgrst, 'reload schema';

-- 1. Ensure columns exist and have proper defaults
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_reliever BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS parent_supervisor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- 2. Clean up any existing NULLs
UPDATE public.profiles SET is_reliever = false WHERE is_reliever IS NULL;

-- 3. If any supervisor is currently marked as reliever, link them to the primary supervisor:
-- (e.g. if 'P2' is the reliever for 'Puneet', set parent_supervisor_id)
UPDATE public.profiles
SET is_reliever = true,
    parent_supervisor_id = (SELECT id FROM public.profiles WHERE full_name = 'Puneet' AND (is_reliever IS NULL OR is_reliever = false) LIMIT 1)
WHERE full_name = 'P2';

-- 4. Reload schema cache
NOTIFY pgrst, 'reload schema';