-- Ever Roots three-tier billing model foundation.
--
-- Local schema preparation only. Do not deploy until App Store Connect product
-- IDs and Apple transaction validation are ready.

alter table public.family_entitlements
  add column if not exists apple_original_transaction_id text,
  add column if not exists apple_product_id text,
  add column if not exists apple_environment text,
  add column if not exists offer_type text,
  add column if not exists offer_identifier text;

alter table public.family_entitlements
  drop constraint if exists family_entitlements_plan_check;

alter table public.family_entitlements
  add constraint family_entitlements_plan_check
  check (plan in ('free', 'everroot_family', 'everroot_legacy'));

alter table public.family_entitlements
  drop constraint if exists family_entitlements_status_check;

alter table public.family_entitlements
  add constraint family_entitlements_status_check
  check (
    status in (
      'free',
      'active',
      'grace_period',
      'billing_retry',
      'expired',
      'cancelled',
      'refunded',
      'revoked'
    )
  );

alter table public.family_entitlements
  drop constraint if exists family_entitlements_apple_environment_check;

alter table public.family_entitlements
  add constraint family_entitlements_apple_environment_check
  check (
    apple_environment is null
    or apple_environment in ('sandbox', 'production')
  );

create unique index if not exists family_entitlements_apple_original_tx_unique
  on public.family_entitlements(apple_original_transaction_id)
  where apple_original_transaction_id is not null;

create index if not exists family_entitlements_apple_product_idx
  on public.family_entitlements(apple_product_id)
  where apple_product_id is not null;

create or replace function public.everroot_family_plan(p_family_id uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when fe.plan in ('everroot_family', 'everroot_legacy')
       and fe.status in ('active', 'grace_period')
       and (
         fe.current_period_end is null
         or fe.current_period_end > now()
       )
      then fe.plan
      else 'free'
    end
    from public.family_entitlements fe
    where fe.family_id = p_family_id
    limit 1
  ), 'free');
$$;

create or replace function public.everroot_limits(p_family_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case public.everroot_family_plan(p_family_id)
    when 'everroot_legacy' then jsonb_build_object(
      'plan', 'everroot_legacy',
      'real_members', 30,
      'legacy_people', 250,
      'memories', 3000,
      'photos', 6000,
      'voice_notes', 1500,
      'storage_bytes', 53687091200,
      'ai_responses_monthly', 1500,
      'transcription_seconds_monthly', 120000,
      'invites_monthly', 100,
      'pending_invites', 50,
      'voice_seconds', 300
    )
    when 'everroot_family' then jsonb_build_object(
      'plan', 'everroot_family',
      'real_members', 20,
      'legacy_people', 100,
      'memories', 1000,
      'photos', 2000,
      'voice_notes', 500,
      'storage_bytes', 10737418240,
      'ai_responses_monthly', 500,
      'transcription_seconds_monthly', 36000,
      'invites_monthly', 50,
      'pending_invites', 25,
      'voice_seconds', 120
    )
    else jsonb_build_object(
      'plan', 'free',
      'real_members', 8,
      'legacy_people', 8,
      'memories', 100,
      'photos', 100,
      'voice_notes', 25,
      'storage_bytes', 524288000,
      'ai_responses_monthly', 20,
      'transcription_seconds_monthly', 600,
      'invites_monthly', 25,
      'pending_invites', 10,
      'voice_seconds', 120
    )
  end;
$$;

revoke all on function public.everroot_family_plan(uuid)
  from public, anon, authenticated;
revoke all on function public.everroot_limits(uuid)
  from public, anon, authenticated;
grant execute on function public.everroot_family_plan(uuid) to service_role;
grant execute on function public.everroot_limits(uuid) to service_role;

comment on column public.family_entitlements.apple_original_transaction_id
  is 'Apple original transaction id for the family subscription. Set only by the trusted validation backend.';
comment on column public.family_entitlements.apple_product_id
  is 'Current App Store subscription product id mapped to the family entitlement.';
comment on column public.family_entitlements.apple_environment
  is 'Apple transaction environment: sandbox or production.';
comment on column public.family_entitlements.offer_type
  is 'Apple introductory, promotional, or offer-code type when present.';
comment on column public.family_entitlements.offer_identifier
  is 'Apple offer identifier when a founding-family or promotional offer is used.';
