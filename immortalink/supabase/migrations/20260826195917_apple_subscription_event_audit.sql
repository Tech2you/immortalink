-- Audit trail for Apple subscription validation and server notifications.

create table if not exists public.apple_subscription_events (
  id uuid primary key default gen_random_uuid(),
  family_id uuid references public.family_groups(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  event_source text not null,
  apple_environment text,
  apple_product_id text,
  apple_original_transaction_id text,
  apple_transaction_id text,
  notification_type text,
  subtype text,
  entitlement_status text,
  raw_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint apple_subscription_events_source_check
    check (event_source in ('client_validation', 'server_notification')),
  constraint apple_subscription_events_environment_check
    check (
      apple_environment is null
      or apple_environment in ('sandbox', 'production')
    )
);

create index if not exists apple_subscription_events_family_created_idx
  on public.apple_subscription_events(family_id, created_at desc);

create index if not exists apple_subscription_events_original_tx_idx
  on public.apple_subscription_events(apple_original_transaction_id)
  where apple_original_transaction_id is not null;

alter table public.apple_subscription_events enable row level security;

drop policy if exists "family owners can view apple subscription events"
  on public.apple_subscription_events;
create policy "family owners can view apple subscription events"
  on public.apple_subscription_events
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.family_members fm
      where fm.family_id = apple_subscription_events.family_id
        and fm.user_id = auth.uid()
        and fm.role = 'owner'
    )
  );

revoke all on table public.apple_subscription_events from public, anon;
grant select on table public.apple_subscription_events to authenticated;
grant all on table public.apple_subscription_events to service_role;
