-- Billing only: no tree, private-vault or legacy editing policies change.
create table public.family_sponsor_reservations (
  family_id uuid primary key references public.family_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reserved_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '15 minutes'
);
-- Keep the original purchaser binding even after the user/family is deleted.
-- No names, emails or Apple credentials are stored in this ledger.
create table public.apple_sponsor_bindings (
  original_transaction_id text primary key,
  environment text not null check (environment in ('sandbox','production')),
  purchaser_id uuid,
  family_id uuid references public.family_groups(id) on delete set null,
  retired boolean not null default false,
  last_purchase_at timestamptz,
  last_signed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.family_sponsor_reservations enable row level security;
alter table public.apple_sponsor_bindings enable row level security;
revoke all on public.family_sponsor_reservations, public.apple_sponsor_bindings from public, anon, authenticated;
grant all on public.family_sponsor_reservations, public.apple_sponsor_bindings to service_role;
-- Preserve a bounded, private recovery record per transaction/reason. No raw
-- signed payload, email or name is required to reconcile a conflicting charge.
create table public.apple_sponsorship_conflicts (
  original_transaction_id text not null,
  transaction_id text not null,
  reason text not null,
  family_id uuid references public.family_groups(id) on delete set null,
  purchaser_id uuid references auth.users(id) on delete set null,
  environment text not null check (environment in ('sandbox','production')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key(transaction_id,environment,reason)
);
alter table public.apple_sponsorship_conflicts enable row level security;
revoke all on public.apple_sponsorship_conflicts from public,anon,authenticated;
grant all on public.apple_sponsorship_conflicts to service_role;
create function public.record_apple_sponsorship_conflict(
  p_transaction jsonb,p_reason text,p_family_id uuid,p_user_id uuid
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
  insert into public.apple_sponsorship_conflicts(original_transaction_id,transaction_id,reason,family_id,purchaser_id,environment)
  values(p_transaction->>'originalTransactionId',p_transaction->>'transactionId',p_reason,p_family_id,
    (select id from auth.users where id=p_user_id),lower(p_transaction->>'environment'))
  on conflict(transaction_id,environment,reason) do update set last_seen_at=now();
  return jsonb_build_object('applied',false,'code',p_reason);
end;
$$;
revoke all on function public.record_apple_sponsorship_conflict(jsonb,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.record_apple_sponsorship_conflict(jsonb,text,uuid,uuid) to service_role;
-- Sponsorship summaries are shared; raw Apple transaction payloads are not.
revoke all on public.apple_subscription_events from authenticated;
drop policy if exists "family owners can view apple subscription events" on public.apple_subscription_events;

insert into public.apple_sponsor_bindings(original_transaction_id,environment,purchaser_id,family_id)
select apple_original_transaction_id,apple_environment,billing_owner_user_id,family_id
from public.family_entitlements
where apple_original_transaction_id is not null and apple_environment in ('sandbox','production');

create function public.reserve_family_sponsorship(p_family_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_ent public.family_entitlements%rowtype;
  v_res public.family_sponsor_reservations%rowtype;
begin
  if v_user is null then raise exception 'FAMILY_MEMBERSHIP_REQUIRED' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtext('sponsor-user:'||v_user::text));
  perform pg_advisory_xact_lock(hashtext(p_family_id::text));
  if v_user is null or not exists(select 1 from public.family_members
    where family_id=p_family_id and user_id=v_user) then
    raise exception 'FAMILY_MEMBERSHIP_REQUIRED' using errcode='42501';
  end if;
  if exists(select 1 from public.family_sponsor_reservations where user_id=v_user
    and family_id<>p_family_id and expires_at>now()) then
    raise exception 'SPONSOR_PURCHASE_IN_PROGRESS';
  end if;
  if exists(select 1 from public.family_entitlements where billing_owner_user_id=v_user
    and family_id<>p_family_id and status in ('active','grace_period')
    and (current_period_end is null or current_period_end>now())) then
    raise exception 'SPONSOR_ALREADY_SUPPORTS_FAMILY';
  end if;
  select * into v_ent from public.family_entitlements where family_id=p_family_id;
  if v_ent.status in ('active','grace_period') and
     (v_ent.current_period_end is null or v_ent.current_period_end > now()) and
     v_ent.billing_owner_user_id is distinct from v_user then
    raise exception 'FAMILY_ALREADY_SPONSORED' using errcode='P0001';
  end if;
  select * into v_res from public.family_sponsor_reservations where family_id=p_family_id;
  if v_res.expires_at > now() and v_res.user_id <> v_user then
    raise exception 'SPONSOR_PURCHASE_IN_PROGRESS' using errcode='P0001';
  end if;
  if v_res.expires_at > now() and v_res.user_id = v_user then
    return; -- Repeated taps must not extend a reservation indefinitely.
  end if;
  insert into public.family_sponsor_reservations(family_id,user_id)
  values(p_family_id,v_user)
  on conflict(family_id) do update set user_id=excluded.user_id,
    reserved_at=now(),expires_at=now()+interval '15 minutes';
end;
$$;
revoke all on function public.reserve_family_sponsorship(uuid) from public,anon;
grant execute on function public.reserve_family_sponsorship(uuid) to authenticated;

-- Only trusted Edge Functions may submit an Apple-verified transaction.
-- Locking, purchaser binding, old-sponsor retirement and entitlement application
-- must commit together; neither a client nor a notification writes around this.
create function public.apply_verified_family_subscription(
  p_transaction jsonb, p_family_id uuid, p_user_id uuid,
  p_source text, p_notification_type text default null
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_original text := nullif(p_transaction->>'originalTransactionId','');
  v_tx text := nullif(p_transaction->>'transactionId','');
  v_product text := p_transaction->>'productId';
  v_env text := lower(p_transaction->>'environment');
  v_token text := lower(nullif(p_transaction->>'appAccountToken',''));
  v_family uuid := p_family_id;
  v_binding public.apple_sponsor_bindings%rowtype;
  v_bound boolean;
  v_ent public.family_entitlements%rowtype;
  v_plan text;
  v_status text;
  v_end timestamptz := to_timestamp((p_transaction->>'expiresDate')::numeric/1000);
  v_purchase timestamptz := to_timestamp((p_transaction->>'purchaseDate')::numeric/1000);
  v_signed timestamptz := to_timestamp((p_transaction->>'signedDate')::numeric/1000);
begin
  if p_source not in ('client_validation','server_notification') or p_source is null or
     v_original is null or v_tx is null or v_env not in ('sandbox','production') or v_env is null or
     v_end is null or v_purchase is null or v_signed is null or
     p_transaction->>'bundleId' is distinct from 'com.everroots.app' then
    raise exception 'APPLE_TRANSACTION_INVALID';
  end if;
  v_plan := case v_product
    when 'everroots.family.monthly' then 'everroot_family'
    when 'everroots.family.annual' then 'everroot_family'
    when 'everroots.legacy.monthly' then 'everroot_legacy'
    when 'everroots.legacy.annual' then 'everroot_legacy' end;
  if v_plan is null then raise exception 'APPLE_PRODUCT_UNSUPPORTED'; end if;
  -- Serialize the subscription first, then its single bound family.
  perform pg_advisory_xact_lock(hashtext('apple:' || v_original));
  select * into v_binding from public.apple_sponsor_bindings where original_transaction_id=v_original;
  v_bound := found;
  if v_bound then
    if v_binding.environment <> v_env then raise exception 'APPLE_ENVIRONMENT_MISMATCH'; end if;
    if p_source='client_validation' and (v_binding.purchaser_id is distinct from p_user_id or
      v_binding.family_id is distinct from p_family_id) then
      raise exception 'APPLE_PURCHASE_ALREADY_BOUND';
    end if;
    v_family := v_binding.family_id;
    if v_binding.retired or v_family is null then
      return public.record_apple_sponsorship_conflict(p_transaction,'APPLE_SPONSOR_REPLACED',v_family,v_binding.purchaser_id);
    end if;
  elsif p_source='server_notification' then
    return public.record_apple_sponsorship_conflict(p_transaction,'APPLE_PURCHASE_UNMATCHED',null,null);
  end if;
  if v_family is null then raise exception 'FAMILY_MEMBERSHIP_REQUIRED'; end if;
  perform pg_advisory_xact_lock(hashtext(v_family::text));
  -- Another subscription may have replaced this chain while we waited.
  if v_bound then
    select * into v_binding from public.apple_sponsor_bindings where original_transaction_id=v_original;
    if v_binding.retired then
      return public.record_apple_sponsorship_conflict(p_transaction,'APPLE_SPONSOR_REPLACED',v_family,v_binding.purchaser_id);
    end if;
  end if;
  if p_source='client_validation' then
    if p_user_id is null or not exists(select 1 from public.family_members
      where family_id=v_family and user_id=p_user_id) then
      raise exception 'FAMILY_MEMBERSHIP_REQUIRED' using errcode='42501';
    end if;
    if v_token is not null and v_token <> p_user_id::text then
      raise exception 'APPLE_PURCHASER_MISMATCH';
    end if;
    if not v_bound and (v_token is null or not exists(select 1 from public.family_sponsor_reservations
      where family_id=v_family and user_id=p_user_id and v_purchase >= reserved_at - interval '1 minute'
        and v_purchase <= expires_at)) then
      return public.record_apple_sponsorship_conflict(p_transaction,'APPLE_PURCHASER_UNVERIFIED',v_family,p_user_id);
    end if;
  end if;
  select * into v_ent from public.family_entitlements where family_id=v_family for update;
  -- Backfilled bindings may pre-date event timestamps in the ledger.
  if v_bound and v_binding.last_purchase_at is null and v_end < v_ent.current_period_end
     and p_transaction->>'revocationDate' is null and coalesce(p_notification_type,'') not in ('REFUND','REVOKE') then
    return jsonb_build_object('applied',true,'code','APPLE_EVENT_STALE',
      'plan',v_ent.plan,'status',v_ent.status,'product_id',v_product,'current_period_end',v_ent.current_period_end);
  end if;
  if v_ent.apple_original_transaction_id is distinct from v_original and
     v_ent.status in ('active','grace_period') and
     (v_ent.current_period_end is null or v_ent.current_period_end > now()) then
    return public.record_apple_sponsorship_conflict(p_transaction,'FAMILY_ALREADY_SPONSORED',v_family,p_user_id);
  end if;
  if v_bound and (v_purchase < v_binding.last_purchase_at or
      (v_purchase = v_binding.last_purchase_at and v_signed <= v_binding.last_signed_at)) then
    return jsonb_build_object('applied',true,'code','APPLE_EVENT_STALE',
      'plan',v_ent.plan,'status',v_ent.status,'product_id',v_product,'current_period_end',v_ent.current_period_end);
  end if;
  v_status := case when p_transaction->>'revocationDate' is not null or p_notification_type='REFUND' then 'refunded'
    when p_notification_type='REVOKE' then 'revoked'
    when v_end <= now() then 'expired' else 'active' end;
  -- Never replace a sponsor with an expired historical purchase during restore.
  if not v_bound and v_status <> 'active' then
    return jsonb_build_object('applied',false,'code','APPLE_SUBSCRIPTION_INACTIVE');
  end if;
  insert into public.apple_sponsor_bindings(original_transaction_id,environment,purchaser_id,family_id,last_purchase_at,last_signed_at)
  values(v_original,v_env,p_user_id,v_family,v_purchase,v_signed)
  on conflict(original_transaction_id) do update set last_purchase_at=excluded.last_purchase_at,last_signed_at=excluded.last_signed_at;
  update public.apple_sponsor_bindings set retired=true
    where family_id=v_family and original_transaction_id<>v_original;
  insert into public.family_entitlements(family_id,plan,status,provider,provider_entitlement_id,
    provider_subscription_id,billing_owner_user_id,current_period_end,apple_original_transaction_id,
    apple_product_id,apple_environment)
  values(v_family,case when v_status='active' then v_plan else 'free' end,v_status,'apple',v_tx,
    v_original,case when v_bound then v_ent.billing_owner_user_id else p_user_id end,v_end,v_original,v_product,v_env)
  on conflict(family_id) do update set plan=excluded.plan,status=excluded.status,provider='apple',
    provider_entitlement_id=excluded.provider_entitlement_id,provider_subscription_id=excluded.provider_subscription_id,
    billing_owner_user_id=excluded.billing_owner_user_id,current_period_end=excluded.current_period_end,
    apple_original_transaction_id=excluded.apple_original_transaction_id,apple_product_id=excluded.apple_product_id,
    apple_environment=excluded.apple_environment,updated_at=now();
  insert into public.apple_subscription_events(family_id,user_id,event_source,apple_environment,
    apple_product_id,apple_original_transaction_id,apple_transaction_id,notification_type,entitlement_status,raw_payload)
  values(v_family,case when p_source='client_validation' then p_user_id else null end,p_source,v_env,
    v_product,v_original,v_tx,p_notification_type,v_status,p_transaction);
  return jsonb_build_object('applied',true,'plan',v_plan,'status',v_status,'product_id',v_product,'current_period_end',v_end);
end;
$$;
revoke all on function public.apply_verified_family_subscription(jsonb,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.apply_verified_family_subscription(jsonb,uuid,uuid,text,text) to service_role;

create function public.get_family_sponsorship(p_family_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_ent public.family_entitlements%rowtype; v_name text;
begin
  if auth.uid() is null or not exists(select 1 from public.family_members
    where family_id=p_family_id and user_id=auth.uid()) then
    raise exception 'FAMILY_MEMBERSHIP_REQUIRED' using errcode='42501';
  end if;
  select * into v_ent from public.family_entitlements where family_id=p_family_id;
  select coalesce(nullif(btrim(v.display_name),''),nullif(btrim(v.name),''),'Family member')
    into v_name from public.vaults v join public.family_members fm on fm.user_id=v.owner_id
    where fm.family_id=p_family_id and v.owner_id=v_ent.billing_owner_user_id
    order by v.created_at,v.id limit 1;
  return jsonb_build_object('active',coalesce(v_ent.status in ('active','grace_period') and
      (v_ent.current_period_end is null or v_ent.current_period_end>now()),false),
    'is_sponsor',coalesce(v_ent.billing_owner_user_id=auth.uid(),false),
    'sponsor_name',coalesce(v_name,'Former member'),'paid_until',v_ent.current_period_end);
end;
$$;
revoke all on function public.get_family_sponsorship(uuid) from public,anon;
grant execute on function public.get_family_sponsorship(uuid) to authenticated;
