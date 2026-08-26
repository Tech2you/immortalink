revoke all on table public.apple_subscription_events
  from public, anon, authenticated;

grant select on table public.apple_subscription_events
  to authenticated;

grant all on table public.apple_subscription_events
  to service_role;
