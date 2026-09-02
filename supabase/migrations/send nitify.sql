INSERT INTO public.notifications (org_id, user_id, title, body, type)
SELECT 
  org_id, 
  id, 
  '🚨 Urgent Shift Update', 
  'Your shift timing has been confirmed at Station A (TOM Counter 1).',
  'shift_alert'
FROM public.profiles
WHERE fcm_token IS NOT NULL
LIMIT 1;