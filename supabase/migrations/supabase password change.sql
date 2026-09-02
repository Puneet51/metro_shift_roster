-- Change email and password for Puneet (Admin)
UPDATE public.profiles
SET 
  email = 'puneet56511@gmail.com',                      -- Put new or current email here
  admin_password_hash = crypt('YourNewPasswordHere', gen_salt('bf')) -- Put new password here
WHERE role = 'admin' AND email = 'puneet56511@gmail.com';

-- Refresh schema cache
NOTIFY pgrst, 'reload schema';