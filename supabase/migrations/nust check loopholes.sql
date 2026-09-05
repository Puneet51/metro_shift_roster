WITH table_checks AS (
  -- 1. Check if any table is completely missing RLS
  SELECT 
    'MISSING RLS' AS issue_type,
    tablename AS target_name,
    'CRITICAL: Row Level Security is disabled!' AS description
  FROM pg_tables
  WHERE schemaname = 'public'
    AND rowsecurity = false
    AND tablename IN ('profiles', 'shifts', 'shift_assignments', 'attendance', 'stations')

  UNION ALL

  -- 2. Check for wildcard policies (USING true / WITH CHECK true) accessible by anon or public
  SELECT 
    'WILDCARD POLICY' AS issue_type,
    tablename || ' -> ' || policyname AS target_name,
    'CRITICAL: Policy allows anyone (USING true) on ' || cmd AS description
  FROM pg_policies
  WHERE schemaname = 'public'
    AND (
      'anon' = ANY(roles) 
      OR 'public' = ANY(roles)
      OR roles = '{public}'
    )
    AND (
      qual = 'true' 
      OR with_check = 'true'
    )

  UNION ALL

  -- 3. Check for write permissions granted to 'anon'
  SELECT 
    'ANON WRITE PERMISSION' AS issue_type,
    table_name AS target_name,
    'HIGH: anon role has ' || privilege_type || ' privileges on this table' AS description
  FROM information_schema.role_table_grants
  WHERE grantee = 'anon'
    AND table_schema = 'public'
    AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE')

  UNION ALL

  -- 4. Check for critical RPCs granted to anon / PUBLIC
  SELECT 
    'PUBLIC RPC ACCESS' AS issue_type,
    routine_name AS target_name,
    'HIGH: Anyone can call this function anonymously!' AS description
  FROM information_schema.routine_privileges
  WHERE routine_schema = 'public'
    AND grantee IN ('anon', 'PUBLIC')
    AND routine_name IN ('set_user_custom_pin', 'set_staff_phone_auth', 'verify_admin_login')
)
SELECT * FROM table_checks;