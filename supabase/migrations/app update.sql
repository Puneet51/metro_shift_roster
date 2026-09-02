-- 1. Add is_active column to profiles (default true)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

-- 2. Create app_config table for remote version checking and mandatory force update toggle
CREATE TABLE IF NOT EXISTS public.app_config (
  id INT PRIMARY KEY DEFAULT 1,
  min_version TEXT NOT NULL DEFAULT '1.0.0',
  latest_version TEXT NOT NULL DEFAULT '1.0.0',
  force_update BOOLEAN NOT NULL DEFAULT false,
  update_url TEXT DEFAULT '',
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert baseline configuration row if missing
INSERT INTO public.app_config (id, min_version, latest_version, force_update)
VALUES (1, '1.0.0', '1.0.0', false)
ON CONFLICT (id) DO NOTHING;

NOTIFY pgrst, 'reload schema';

-- 1. Ensure app_versions table has all required columns
CREATE TABLE IF NOT EXISTS public.app_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  platform TEXT UNIQUE NOT NULL,
  latest_version TEXT NOT NULL DEFAULT '1.0.0',
  min_version TEXT NOT NULL DEFAULT '1.0.0',
  update_url TEXT DEFAULT '',
  release_notes TEXT DEFAULT '',
  force_update BOOLEAN DEFAULT false,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. If app_versions already existed, add the missing columns
ALTER TABLE public.app_versions ADD COLUMN IF NOT EXISTS force_update BOOLEAN DEFAULT false;
ALTER TABLE public.app_versions ADD COLUMN IF NOT EXISTS min_version TEXT DEFAULT '1.0.0';
ALTER TABLE public.app_versions ADD COLUMN IF NOT EXISTS latest_version TEXT DEFAULT '1.0.0';
ALTER TABLE public.app_versions ADD COLUMN IF NOT EXISTS update_url TEXT DEFAULT '';
ALTER TABLE public.app_versions ADD COLUMN IF NOT EXISTS release_notes TEXT DEFAULT '';

-- 3. Add reliever supervisor support column in profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_reliever BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS parent_supervisor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- 4. Refresh PostgREST schema cache to clear PGRST204
NOTIFY pgrst, 'reload schema';

-- 1. Remove duplicate platform entries by casting platform to text
DELETE FROM public.app_versions a
USING public.app_versions b
WHERE a.ctid < b.ctid 
  AND a.platform::text = b.platform::text;

-- 2. Drop existing constraint if it exists
ALTER TABLE public.app_versions 
  DROP CONSTRAINT IF EXISTS uq_app_versions_platform;

-- 3. Add the unique constraint on the platform column
ALTER TABLE public.app_versions 
  ADD CONSTRAINT uq_app_versions_platform UNIQUE (platform);

-- 4. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';


-- 1. Ensure version column exists and allows nulls or defaults to latest_version
ALTER TABLE public.app_versions ADD COLUMN IF NOT EXISTS latest_version TEXT;
ALTER TABLE public.app_versions ADD COLUMN IF NOT EXISTS min_version TEXT;

-- If 'version' column exists with NOT NULL, drop the constraint or sync it
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'app_versions' AND column_name = 'version'
  ) THEN
    ALTER TABLE public.app_versions ALTER COLUMN version DROP NOT NULL;
  ELSE
    ALTER TABLE public.app_versions ADD COLUMN version TEXT;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';



-- 1. Remove strict NOT NULL constraints from all version columns
ALTER TABLE public.app_versions ALTER COLUMN version DROP NOT NULL;
ALTER TABLE public.app_versions ALTER COLUMN min_supported_version DROP NOT NULL;

-- 2. Ensure all column variations exist
ALTER TABLE public.app_versions ADD COLUMN IF NOT EXISTS latest_version TEXT;
ALTER TABLE public.app_versions ADD COLUMN IF NOT EXISTS min_version TEXT;

-- 3. Set default fallbacks so missing fields never trigger null violations
ALTER TABLE public.app_versions ALTER COLUMN min_supported_version SET DEFAULT '1.0.0';
ALTER TABLE public.app_versions ALTER COLUMN min_version SET DEFAULT '1.0.0';
ALTER TABLE public.app_versions ALTER COLUMN latest_version SET DEFAULT '1.0.0';
ALTER TABLE public.app_versions ALTER COLUMN version SET DEFAULT '1.0.0';

NOTIFY pgrst, 'reload schema';

ALTER TYPE platform_type ADD VALUE IF NOT EXISTS 'web';
INSERT INTO public.app_versions (
  platform,
  version,
  latest_version,
  min_version,
  min_supported_version,
  update_url,
  description,
  is_mandatory,
  force_update
) VALUES (
  'web',
  '1.0.0',
  '1.0.0',
  '1.0.0',
  '1.0.0',
  'https://metroshiftroster.web.app',
  'Web version is up to date',
  false,
  false
)
ON CONFLICT (platform) DO NOTHING;

NOTIFY pgrst, 'reload schema';