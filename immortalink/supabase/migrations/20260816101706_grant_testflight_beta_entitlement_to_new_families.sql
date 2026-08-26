create or replace function public.everroot_grant_testflight_beta_entitlement()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.family_entitlements (
    family_id,
    plan,
    status,
    provider,
    provider_subscription_id,
    billing_owner_user_id,
    current_period_start,
    current_period_end,
    cancel_at_period_end,
    updated_at
  )
  values (
    new.id,
    'everroot_family',
    'active',
    'testflight_beta_auto',
    'testflight_beta_' || new.id::text,
    new.created_by,
    now(),
    timestamp with time zone '2026-11-14 23:59:59+00',
    false,
    now()
  )
  on conflict (family_id) do update
    set plan = 'everroot_family',
        status = 'active',
        provider = 'testflight_beta_auto',
        provider_subscription_id = 'testflight_beta_' || excluded.family_id::text,
        billing_owner_user_id = excluded.billing_owner_user_id,
        current_period_start = excluded.current_period_start,
        current_period_end = excluded.current_period_end,
        cancel_at_period_end = false,
        updated_at = now()
    where family_entitlements.plan = 'free'
       or family_entitlements.status = 'free'
       or family_entitlements.provider is null
       or family_entitlements.provider = 'testflight_beta_auto';

  return new;
end;
$$;

drop trigger if exists everroot_testflight_beta_family_entitlement_after_insert
  on public.family_groups;

create trigger everroot_testflight_beta_family_entitlement_after_insert
after insert on public.family_groups
for each row
execute function public.everroot_grant_testflight_beta_entitlement();
