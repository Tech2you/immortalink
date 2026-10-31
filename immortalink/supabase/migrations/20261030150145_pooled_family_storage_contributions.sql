-- Each verified Apple chain contributes once. Existing paid grants retain their
-- advertised allowance; new bucket checkouts use 5/25 GB. No media is rewritten.
create schema if not exists heiro_billing;
revoke all on schema heiro_billing from public,anon,authenticated;
grant usage on schema heiro_billing to service_role;

alter table public.family_entitlements add column storage_model_version integer not null default 1
  check(storage_model_version in (1,2));
drop index public.family_entitlements_family_unique;
create unique index family_entitlements_manual_unique on public.family_entitlements(family_id)
  where provider is distinct from 'apple';
create index family_entitlements_family_active on public.family_entitlements(family_id,status,current_period_end);
create index family_entitlements_purchaser_active on public.family_entitlements(billing_owner_user_id,status,current_period_end);
alter table public.family_sponsor_reservations drop constraint family_sponsor_reservations_pkey;
alter table public.family_sponsor_reservations add primary key(family_id,user_id);
alter table public.family_sponsor_reservations add column bucket_model boolean not null default false;
alter table public.family_sponsor_checkout_attempts add column bucket_model boolean not null default false;

create function heiro_billing.storage_grant(p_plan text,p_version integer) returns bigint
language sql immutable set search_path='' as $$
 select (case p_plan when 'everroot_family' then 5 when 'everroot_legacy' then 25 else 0 end)::bigint
   *1073741824*(case when p_version=1 then 2 else 1 end);
$$;
revoke all on function heiro_billing.storage_grant(text,integer) from public,anon,authenticated;
grant execute on function heiro_billing.storage_grant(text,integer) to service_role;


CREATE OR REPLACE FUNCTION heiro_billing.reserve_contribution(p_family_id uuid,p_bucket boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid := auth.uid();
  v_ent public.family_entitlements%rowtype;
  v_res public.family_sponsor_reservations%rowtype;
begin
  if p_bucket is distinct from true then raise exception 'APP_UPDATE_REQUIRED'; end if;
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
  if exists(select 1 from public.family_sponsor_reservations where family_id=p_family_id
    and user_id<>v_user and expires_at>now() and (not p_bucket or not bucket_model)) then
    raise exception 'SPONSOR_PURCHASE_IN_PROGRESS';
  end if;
  select * into v_res from public.family_sponsor_reservations where family_id=p_family_id and user_id=v_user;
  if v_res.expires_at>now() and v_res.bucket_model is distinct from p_bucket then
    raise exception 'SPONSOR_PURCHASE_IN_PROGRESS';
  end if;
  if v_res.expires_at > now() and v_res.user_id = v_user then
    return; -- Repeated taps must not extend a reservation indefinitely.
  end if;
  insert into public.family_sponsor_reservations(family_id,user_id,bucket_model)
  values(p_family_id,v_user,p_bucket)
  on conflict(family_id,user_id) do update set bucket_model=excluded.bucket_model,
    reservation_id=gen_random_uuid(),reserved_at=now(),expires_at=now()+interval '15 minutes';
end;
$function$;


revoke all on function heiro_billing.reserve_contribution(uuid,boolean) from public,anon,authenticated;
grant execute on function heiro_billing.reserve_contribution(uuid,boolean) to service_role;
create or replace function public.reserve_family_sponsorship(p_family_id uuid) returns void
language sql security definer set search_path='' as $$select heiro_billing.reserve_contribution(p_family_id,false)$$;


CREATE OR REPLACE FUNCTION heiro_billing.begin_contribution(p_family_id uuid,p_bucket boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.family_sponsor_reservations%rowtype;
begin
  perform heiro_billing.reserve_contribution(p_family_id,p_bucket);
  if (select count(*) from public.family_sponsor_checkout_attempts
      where user_id=auth.uid() and reserved_at>now()-interval '1 minute') >= 6 then
    raise exception 'SPONSOR_CHECKOUT_RATE_LIMIT' using errcode='P0001';
  end if;
  select * into strict r from public.family_sponsor_reservations
    where family_id=p_family_id and user_id=auth.uid();
  insert into public.family_sponsor_checkout_attempts(reservation_id,family_id,user_id,reserved_at,expires_at,bucket_model)
  values(r.reservation_id,r.family_id,r.user_id,r.reserved_at,r.expires_at,r.bucket_model)
  on conflict(reservation_id) do nothing;
  return jsonb_build_object('reservation_id',r.reservation_id,'expires_at',r.expires_at);
end;
$function$;


revoke all on function heiro_billing.begin_contribution(uuid,boolean) from public,anon;
grant execute on function heiro_billing.begin_contribution(uuid,boolean) to service_role;
create or replace function public.begin_family_sponsorship(p_family_id uuid) returns jsonb
language sql security definer set search_path='' as $$select heiro_billing.begin_contribution(p_family_id,false)$$;
create function public.begin_family_storage_contribution(p_family_id uuid) returns jsonb
language sql security definer set search_path='' as $$select heiro_billing.begin_contribution(p_family_id,true)$$;
revoke all on function public.begin_family_storage_contribution(uuid) from public,anon;
grant execute on function public.begin_family_storage_contribution(uuid) to authenticated;


CREATE OR REPLACE FUNCTION public.prepare_verified_apple_repurchase(p_transaction jsonb, p_family_id uuid, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_original text := nullif(p_transaction->>'originalTransactionId','');
  v_env text := lower(p_transaction->>'environment');
  v_expiry timestamptz := to_timestamp((p_transaction->>'expiresDate')::numeric/1000);
  v_purchase timestamptz := to_timestamp((p_transaction->>'purchaseDate')::numeric/1000);
  v_binding public.apple_sponsor_bindings%rowtype;
  v_family uuid;
begin
  if p_user_id is null or not exists(select 1 from public.family_members
      where family_id=p_family_id and user_id=p_user_id) then
    raise exception 'FAMILY_MEMBERSHIP_REQUIRED';
  end if;
  if v_original is null or v_env is null or v_env not in ('sandbox','production') or
      p_transaction->>'bundleId' is distinct from 'com.everroots.app' or
      p_transaction->>'productId' is null or p_transaction->>'productId' not in (
        'everroots.family.monthly','everroots.family.annual','everroots.legacy.monthly','everroots.legacy.annual') or
      nullif(p_transaction->>'transactionId','') is null or v_expiry is null or v_expiry>now() or
      v_purchase is null or v_purchase>=v_expiry or p_transaction->>'revocationDate' is not null then
    raise exception 'APPLE_SUBSCRIPTION_INACTIVE';
  end if;
  perform pg_advisory_xact_lock(hashtext('apple:'||v_original));
  select * into v_binding from public.apple_sponsor_bindings where original_transaction_id=v_original;
  if not found then raise exception 'APPLE_PURCHASER_UNVERIFIED'; end if;
  if v_binding.environment<>v_env then raise exception 'APPLE_ENVIRONMENT_MISMATCH'; end if;
  if v_purchase<coalesce(v_binding.last_purchase_at,'-infinity'::timestamptz) then
    raise exception 'APPLE_HISTORY_CHECK_UNAVAILABLE';
  end if;
  for v_family in select distinct id from unnest(array[v_binding.family_id,p_family_id]) id
      where id is not null order by id loop
    perform pg_advisory_xact_lock(hashtext(v_family::text));
  end loop;
  -- Retirement also takes the family lock but not the Apple-chain lock.
  select * into v_binding from public.apple_sponsor_bindings where original_transaction_id=v_original;
  if exists(select 1 from public.family_sponsor_reservations
      where family_id=p_family_id and user_id=p_user_id and expires_at>now()) then
    raise exception 'SPONSOR_PURCHASE_IN_PROGRESS';
  end if;
  if exists(select 1 from public.family_entitlements where
      (billing_owner_user_id=p_user_id or apple_original_transaction_id=v_original) and
      status in ('active','grace_period') and (current_period_end is null or current_period_end>now())) then
    raise exception 'APPLE_PREVIOUS_PLAN_NOT_ENDED';
  end if;
  if v_env='sandbox' and exists(select 1 from public.family_entitlements
      where family_id in (p_family_id,v_binding.family_id) and apple_environment='production') then
    raise exception 'APPLE_ENVIRONMENT_MISMATCH';
  end if;
  insert into public.apple_repurchase_checks(original_transaction_id,user_id,family_id,environment,
    binding_snapshot,latest_transaction_id,last_purchase_at,expired_at)
  values(v_original,p_user_id,p_family_id,v_env,to_jsonb(v_binding),p_transaction->>'transactionId',v_purchase,v_expiry)
  on conflict(original_transaction_id,user_id,family_id) do update set
    environment=excluded.environment,binding_snapshot=excluded.binding_snapshot,
    latest_transaction_id=excluded.latest_transaction_id,last_purchase_at=excluded.last_purchase_at,
    expired_at=excluded.expired_at,checked_at=now(),valid_until=now()+interval '15 minutes';
  return jsonb_build_object('code','APPLE_EXPIRED_HISTORY','status','expired');
end $function$;


CREATE OR REPLACE FUNCTION public.apply_verified_family_subscription(p_transaction jsonb, p_family_id uuid, p_user_id uuid, p_source text, p_notification_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_original text := nullif(p_transaction->>'originalTransactionId','');
  v_env text := lower(p_transaction->>'environment');
  v_purchase timestamptz := to_timestamp((p_transaction->>'purchaseDate')::numeric/1000);
  v_end timestamptz := to_timestamp((p_transaction->>'expiresDate')::numeric/1000);
  v_token text := lower(p_transaction->>'appAccountToken');
  v_binding public.apple_sponsor_bindings%rowtype;
  v_check public.apple_repurchase_checks%rowtype;
  v_epoch public.apple_sponsor_reassignments%rowtype;
  v_family uuid;
  v_result jsonb;
  v_reassigned boolean := false;
begin
  if v_original is not null then
    perform pg_advisory_xact_lock(hashtext('apple:'||v_original));
    select * into v_binding from public.apple_sponsor_bindings where original_transaction_id=v_original;
  end if;
  if p_user_id is not null then
    perform pg_advisory_xact_lock(hashtext('sponsor-user:'||p_user_id::text));
  elsif v_binding.purchaser_id is not null then
    perform pg_advisory_xact_lock(hashtext('sponsor-user:'||v_binding.purchaser_id::text));
  end if;
  for v_family in select distinct id from unnest(array[v_binding.family_id,p_family_id]) id
      where id is not null order by id loop
    perform pg_advisory_xact_lock(hashtext(v_family::text));
    if v_env='sandbox' and exists(select 1 from public.family_entitlements
        where family_id=v_family and apple_environment='production') then
      raise exception 'APPLE_ENVIRONMENT_MISMATCH';
    end if;
  end loop;
  select * into v_binding from public.apple_sponsor_bindings where original_transaction_id=v_original;
  if v_binding.original_transaction_id is not null then
    if v_binding.environment is distinct from v_env then raise exception 'APPLE_ENVIRONMENT_MISMATCH'; end if;
    -- A new account's SUBSCRIBED notification may arrive before its client
    -- validation. It must not grant that purchase to the previous family.
    if p_source='server_notification' and not v_binding.retired and v_token is not null and
        v_token is distinct from v_binding.purchaser_id::text then
      return public.record_apple_sponsorship_conflict(p_transaction,'APPLE_PURCHASER_MISMATCH',v_binding.family_id,v_binding.purchaser_id);
    end if;
    select * into v_epoch from public.apple_sponsor_reassignments where original_transaction_id=v_original
      order by purchase_at desc limit 1;
    if found and (v_purchase is null or v_purchase<v_epoch.purchase_at or
        (p_source='server_notification' and v_token is distinct from v_binding.purchaser_id::text)) then
      return public.record_apple_sponsorship_conflict(p_transaction,'APPLE_EVENT_PREVIOUS_SPONSOR',v_binding.family_id,v_binding.purchaser_id);
    end if;
    if p_source='client_validation' and (v_binding.purchaser_id is distinct from p_user_id or
        v_binding.family_id is distinct from p_family_id) then
      select * into v_check from public.apple_repurchase_checks where
        original_transaction_id=v_original and user_id=p_user_id and family_id=p_family_id;
      if not found or v_check.environment is distinct from v_env or
          v_check.binding_snapshot->'purchaser_id' is distinct from to_jsonb(v_binding)->'purchaser_id' or
          v_check.binding_snapshot->'family_id' is distinct from to_jsonb(v_binding)->'family_id' or
          v_check.binding_snapshot->'created_at' is distinct from to_jsonb(v_binding)->'created_at' or
          v_binding.last_purchase_at>v_check.last_purchase_at or
          v_token is distinct from p_user_id::text or
          p_transaction->>'transactionReason' is distinct from 'PURCHASE' or
          nullif(p_transaction->>'transactionId','') is null or
          p_transaction->>'transactionId'=v_check.latest_transaction_id or
          v_purchase is null or v_purchase<=v_check.checked_at or v_purchase>v_check.valid_until or
          v_purchase<=v_check.last_purchase_at or v_purchase<=v_check.expired_at or
          v_purchase>now()+interval '1 minute' or v_end is null or v_end<=now() or
          p_transaction->>'revocationDate' is not null or p_notification_type is not null or
          not exists(select 1 from public.family_sponsor_checkout_attempts a where
            a.family_id=p_family_id and a.user_id=p_user_id and a.reserved_at>=v_check.checked_at and
            v_purchase>=a.reserved_at and
            v_purchase<=least(a.expires_at,coalesce(a.released_at,a.expires_at))) then
        raise exception 'APPLE_PURCHASE_ALREADY_BOUND';
      end if;
      if p_user_id is null or not exists(select 1 from public.family_members
          where family_id=p_family_id and user_id=p_user_id) then raise exception 'FAMILY_MEMBERSHIP_REQUIRED'; end if;
      if exists(select 1 from public.family_entitlements where
          (billing_owner_user_id=p_user_id or apple_original_transaction_id=v_original) and
          status in ('active','grace_period') and (current_period_end is null or current_period_end>now())) then
        raise exception 'FAMILY_ALREADY_SPONSORED';
      end if;
      insert into public.apple_sponsor_reassignments(original_transaction_id,transaction_id,previous_binding,
        purchaser_id,family_id,purchase_at) values(v_original,p_transaction->>'transactionId',to_jsonb(v_binding),
        p_user_id,p_family_id,v_purchase);
      -- Free the unique current-entitlement pointer, preserving expired billing
      -- history, period, provider reference and append-only transaction events.
      update public.family_entitlements set apple_original_transaction_id=null
        where apple_original_transaction_id=v_original;
      update public.apple_sponsor_bindings set purchaser_id=p_user_id,family_id=p_family_id,
        retired=true,retired_at=v_check.checked_at,last_purchase_at=v_check.last_purchase_at
        where original_transaction_id=v_original;
      v_reassigned := true;
    end if;
  end if;
  v_result := public.apply_verified_family_subscription_internal(
    p_transaction,p_family_id,p_user_id,p_source,p_notification_type);
  if v_reassigned then
    -- Any downstream failure must roll back the audit, pointer and binding too.
    if v_result->>'applied' is distinct from 'true' or v_result->>'status' is distinct from 'active' then
      raise exception 'APPLE_PURCHASE_ALREADY_BOUND';
    end if;
    delete from public.apple_repurchase_checks where original_transaction_id=v_original;
  end if;
  return v_result;
end $function$;


CREATE OR REPLACE FUNCTION public.apply_verified_family_subscription_internal(p_transaction jsonb, p_family_id uuid, p_user_id uuid, p_source text, p_notification_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_owner uuid;
  v_version integer;
  v_bucket boolean;
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
    if v_family is null or (v_binding.retired and p_source='server_notification') then
      return public.record_apple_sponsorship_conflict(p_transaction,'APPLE_SPONSOR_REPLACED',v_family,v_binding.purchaser_id);
    end if;
  elsif p_source='server_notification' then
    return public.record_apple_sponsorship_conflict(p_transaction,'APPLE_PURCHASE_UNMATCHED',null,null);
  end if;
  if v_family is null then raise exception 'FAMILY_MEMBERSHIP_REQUIRED'; end if;
  perform pg_advisory_xact_lock(hashtext(v_family::text));
  if v_bound then
    select * into v_binding from public.apple_sponsor_bindings where original_transaction_id=v_original;
    if v_binding.retired and p_source='server_notification' then
      return public.record_apple_sponsorship_conflict(p_transaction,'APPLE_SPONSOR_REPLACED',v_family,v_binding.purchaser_id);
    end if;
  end if;
  if p_source='client_validation' then
    if p_user_id is null or not exists(select 1 from public.family_members
      where family_id=v_family and user_id=p_user_id) then
      raise exception 'FAMILY_MEMBERSHIP_REQUIRED' using errcode='42501';
    end if;
    -- A retired, expired chain is history, not an entitlement claim. Its
    -- immutable binding above must still match this purchaser and family.
    -- Later transactions in that chain can carry a different appAccountToken.
    if v_bound and v_binding.retired and v_end <= now()
       and p_transaction->>'revocationDate' is null
       and coalesce(p_notification_type,'') not in ('REFUND','REVOKE')
       and not exists(select 1 from public.family_entitlements
         where billing_owner_user_id=p_user_id and apple_original_transaction_id is distinct from v_original
           and status in ('active','grace_period')
           and (current_period_end is null or current_period_end > now())) then
      return jsonb_build_object('applied',true,'code','APPLE_RETIRED_HISTORY',
        'plan','free','status','expired','product_id',v_product,'current_period_end',v_end);
    end if;
    if v_token is not null and v_token <> p_user_id::text then
      raise exception 'APPLE_PURCHASER_MISMATCH';
    end if;
    if not v_bound and (v_token is null or
        not public.has_family_sponsorship_attempt(v_family,p_user_id,v_purchase)) then
      return public.record_apple_sponsorship_conflict(p_transaction,'APPLE_PURCHASER_UNVERIFIED',v_family,p_user_id);
    end if;
  end if;
  v_owner := case when v_bound then v_binding.purchaser_id else p_user_id end;
  select * into v_ent from public.family_entitlements where apple_original_transaction_id=v_original for update;
  -- An owner gets one active subscription, but other family members may each contribute.
  if exists(select 1 from public.family_entitlements where billing_owner_user_id=v_owner
      and apple_original_transaction_id is distinct from v_original and provider='apple'
      and status in ('active','grace_period') and (current_period_end is null or current_period_end>now())) then
    return public.record_apple_sponsorship_conflict(p_transaction,'FAMILY_ALREADY_SPONSORED',v_family,v_owner);
  end if;
  select coalesce(bool_or(bucket_model),false) into v_bucket
    from public.family_sponsor_checkout_attempts where family_id=v_family and user_id=v_owner
      and v_purchase>=reserved_at-interval '1 minute'
      and v_purchase<=least(expires_at,coalesce(released_at,expires_at));
  v_version := coalesce(v_ent.storage_model_version,case when v_bucket then 2 else 1 end);
  -- A restored or renewed legacy purchase keeps the storage that was advertised.
  -- Only an explicit, newly verified bucket checkout changes its offer version.
  if v_bucket and p_source='client_validation' and p_transaction->>'transactionReason'='PURCHASE'
      and (not v_bound or v_purchase>coalesce(v_binding.last_purchase_at,'-infinity')) then
    v_version:=2;
  end if;
  v_status := case when p_transaction->>'revocationDate' is not null or p_notification_type='REFUND' then 'refunded'
    when p_notification_type='REVOKE' then 'revoked'
    when v_end <= now() then 'expired' else 'active' end;
  if v_bound and v_binding.retired then
    -- Require a new, customer-initiated transaction and a checkout made after
    -- retirement. A late renewal or replay cannot take the family back.
    if v_status<>'active' or v_token is distinct from p_user_id::text or
       p_transaction->>'transactionReason' is distinct from 'PURCHASE' or
       v_binding.retired_at is null or v_purchase<=v_binding.retired_at or
       v_purchase<=coalesce(v_binding.last_purchase_at,'-infinity'::timestamptz) or
       not exists(select 1 from public.family_sponsor_checkout_attempts a
         where a.family_id=v_family and a.user_id=p_user_id
           and a.reserved_at>=v_binding.retired_at
           and v_purchase>=a.reserved_at-interval '1 minute'
           and v_purchase<=least(a.expires_at,coalesce(a.released_at,a.expires_at))) then
      return public.record_apple_sponsorship_conflict(p_transaction,'APPLE_SPONSOR_REPLACED',v_family,p_user_id);
    end if;
  else
    if v_bound and v_binding.last_purchase_at is null and v_end < v_ent.current_period_end
       and p_transaction->>'revocationDate' is null and coalesce(p_notification_type,'') not in ('REFUND','REVOKE') then
      return jsonb_build_object('applied',true,'code','APPLE_EVENT_STALE',
        'plan',v_ent.plan,'status',v_ent.status,'product_id',v_product,'current_period_end',v_ent.current_period_end);
    end if;
    if v_bound and (v_purchase < v_binding.last_purchase_at or
        (v_purchase = v_binding.last_purchase_at and v_signed <= v_binding.last_signed_at)) then
      return jsonb_build_object('applied',true,'code','APPLE_EVENT_STALE',
        'plan',v_ent.plan,'status',v_ent.status,'product_id',v_product,'current_period_end',v_ent.current_period_end);
    end if;
  end if;
  if not v_bound and v_status <> 'active' then
    return jsonb_build_object('applied',false,'code','APPLE_SUBSCRIPTION_INACTIVE');
  end if;
  insert into public.apple_sponsor_bindings(original_transaction_id,environment,purchaser_id,family_id,last_purchase_at,last_signed_at)
  values(v_original,v_env,p_user_id,v_family,v_purchase,v_signed)
  on conflict(original_transaction_id) do update set last_purchase_at=excluded.last_purchase_at,
    last_signed_at=excluded.last_signed_at,retired=false,retired_at=null;
  update public.apple_sponsor_bindings set retired=true,retired_at=now()
    where purchaser_id=v_owner and original_transaction_id<>v_original and not retired;
  insert into public.family_entitlements(family_id,plan,status,provider,provider_entitlement_id,
    provider_subscription_id,billing_owner_user_id,current_period_end,apple_original_transaction_id,
    apple_product_id,apple_environment,storage_model_version)
  values(v_family,case when v_status='active' then v_plan else 'free' end,v_status,'apple',v_tx,
    v_original,(select id from auth.users where id=v_owner),
    v_end,v_original,v_product,v_env,v_version)
  on conflict(apple_original_transaction_id) where apple_original_transaction_id is not null
  do update set family_id=excluded.family_id,plan=excluded.plan,status=excluded.status,provider='apple',
    provider_entitlement_id=excluded.provider_entitlement_id,provider_subscription_id=excluded.provider_subscription_id,
    billing_owner_user_id=excluded.billing_owner_user_id,current_period_end=excluded.current_period_end,
    apple_original_transaction_id=excluded.apple_original_transaction_id,apple_product_id=excluded.apple_product_id,
    apple_environment=excluded.apple_environment,storage_model_version=excluded.storage_model_version,updated_at=now();
  insert into public.apple_subscription_events(family_id,user_id,event_source,apple_environment,
    apple_product_id,apple_original_transaction_id,apple_transaction_id,notification_type,entitlement_status,raw_payload)
  values(v_family,case when p_source='client_validation' then p_user_id else null end,p_source,v_env,
    v_product,v_original,v_tx,p_notification_type,v_status,p_transaction);
  return jsonb_build_object('applied',true,'plan',v_plan,'status',v_status,'product_id',v_product,'current_period_end',v_end);
end;
$function$;


CREATE OR REPLACE FUNCTION public.everroot_grant_testflight_beta_entitlement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  on conflict (family_id) where provider is distinct from 'apple' do update
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
$function$;


create or replace function public.everroot_family_plan(p_family_id uuid) returns text
language sql stable security definer set search_path='' as $$
 select case coalesce(max(case plan when 'everroot_legacy' then 2 when 'everroot_family' then 1 else 0 end),0)
  when 2 then 'everroot_legacy' when 1 then 'everroot_family' else 'free' end
 from public.family_entitlements where family_id=p_family_id and status in ('active','grace_period')
  and (current_period_end is null or current_period_end>now());
$$;


CREATE OR REPLACE FUNCTION heiro_billing.tier_limits(p_plan text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case p_plan
    when 'everroot_legacy' then jsonb_build_object(
      'plan', 'everroot_legacy',
      'real_members', null::integer,
      'legacy_people', 250,
      'memories', 3000,
      'photos', 6000,
      'voice_notes', 1500,
      'storage_bytes', 53687091200,
      'ai_responses_monthly', 1500,
      'transcription_seconds_monthly', 24000,
      'invites_monthly', null::integer, 'invites_hourly_per_member', 20, 'invites_hourly_per_family', 50,
      'pending_invites', 50,
      'voice_seconds', 300
    )
    when 'everroot_family' then jsonb_build_object(
      'plan', 'everroot_family',
      'real_members', null::integer,
      'legacy_people', 100,
      'memories', 1000,
      'photos', 2000,
      'voice_notes', 500,
      'storage_bytes', 10737418240,
      'ai_responses_monthly', 500,
      'transcription_seconds_monthly', 7200,
      'invites_monthly', null::integer, 'invites_hourly_per_member', 20, 'invites_hourly_per_family', 50,
      'pending_invites', 25,
      'voice_seconds', 120
    )
    else jsonb_build_object(
      'plan', 'free',
      'real_members', null::integer,
      'legacy_people', 8,
      'memories', 100,
      'photos', 100,
      'voice_notes', 25,
      'storage_bytes', 524288000,
      'ai_responses_monthly', 20,
      'transcription_seconds_monthly', 600,
      'invites_monthly', null::integer, 'invites_hourly_per_member', 20, 'invites_hourly_per_family', 50,
      'pending_invites', 10,
      'voice_seconds', 120
    )
  end;
$function$;


revoke all on function heiro_billing.tier_limits(text) from public,anon,authenticated;
grant execute on function heiro_billing.tier_limits(text) to service_role;

create or replace function public.everroot_limits(p_family_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 with active as (
  select e.*,heiro_billing.tier_limits(e.plan) limits from public.family_entitlements e
  where family_id=p_family_id and status in ('active','grace_period')
    and (current_period_end is null or current_period_end>now())
    and plan in ('everroot_family','everroot_legacy')
 ), pooled as (
  select coalesce(sum(heiro_billing.storage_grant(plan,storage_model_version)) filter(where provider='apple'),0) bytes,
    coalesce(max((limits->>'storage_bytes')::bigint) filter(where provider is distinct from 'apple'),0) grant_bytes,
    coalesce(sum((limits->>'ai_responses_monthly')::bigint) filter(where provider='apple'),0) ai,
    coalesce(sum((limits->>'transcription_seconds_monthly')::bigint) filter(where provider='apple'),0) transcription
  from active
 ), tier as(select heiro_billing.tier_limits(public.everroot_family_plan(p_family_id)) limits)
 select limits || jsonb_build_object('storage_bytes',
   case when greatest(bytes,grant_bytes)>0 then greatest(bytes,grant_bytes) else 524288000 end,
   'ai_responses_monthly',least(2147483647,greatest(ai,(limits->>'ai_responses_monthly')::bigint)),
   'transcription_seconds_monthly',least(2147483647,greatest(transcription,(limits->>'transcription_seconds_monthly')::bigint)))
 from pooled cross join tier;
$$;

create or replace function public.get_family_sponsorship(p_family_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_own public.family_entitlements%rowtype; v_contributors jsonb; v_next timestamptz; v_any boolean; v_count integer; v_beta_bytes bigint; v_beta_until timestamptz;
begin
 if auth.uid() is null or not exists(select 1 from public.family_members
   where family_id=p_family_id and user_id=auth.uid()) then
   raise exception 'FAMILY_MEMBERSHIP_REQUIRED' using errcode='42501';
 end if;
 select * into v_own from public.family_entitlements where family_id=p_family_id
   and billing_owner_user_id=auth.uid() and provider='apple' and status in ('active','grace_period')
   and (current_period_end is null or current_period_end>now()) order by current_period_end desc nulls last limit 1;
 select coalesce(jsonb_agg(jsonb_build_object(
   'name',coalesce(v.name,'Former member'),'is_you',coalesce(e.billing_owner_user_id=auth.uid(),false),
   'plan',e.plan,'storage_bytes',heiro_billing.storage_grant(e.plan,e.storage_model_version),
   'paid_until',e.current_period_end) order by (e.billing_owner_user_id=auth.uid()) desc nulls last,e.created_at,e.id),'[]'::jsonb)
 into v_contributors from (
   select * from public.family_entitlements where family_id=p_family_id and provider='apple'
     and status in ('active','grace_period') and (current_period_end is null or current_period_end>now())
   order by (billing_owner_user_id=auth.uid()) desc nulls last,created_at,id limit 20
 ) e
 left join lateral(select coalesce(nullif(btrim(display_name),''),nullif(btrim(name),''),'Family member') name
   from public.vaults where owner_id=e.billing_owner_user_id
   and exists(select 1 from public.family_members where family_id=p_family_id and user_id=e.billing_owner_user_id)
   order by created_at,id limit 1) v on true
 where e.family_id=p_family_id and e.provider='apple' and e.status in ('active','grace_period')
   and (e.current_period_end is null or e.current_period_end>now());
 select heiro_billing.storage_grant(plan,storage_model_version),current_period_end
 into v_beta_bytes,v_beta_until from public.family_entitlements
 where family_id=p_family_id and provider is distinct from 'apple' and status in ('active','grace_period')
   and (current_period_end is null or current_period_end>now()) limit 1;
 select count(*)>0,min(current_period_end),count(*) filter(where provider='apple') into v_any,v_next,v_count from public.family_entitlements
 where family_id=p_family_id and status in ('active','grace_period')
   and (current_period_end is null or current_period_end>now());
 return jsonb_build_object('bucket_model',true,'active',v_any,'is_sponsor',v_own.id is not null,
   'sponsor_name',null,'paid_until',v_next,'own_plan',v_own.plan,'own_product_id',v_own.apple_product_id,
   'own_paid_until',v_own.current_period_end,'contributor_count',v_count,
   'contributors',v_contributors,'included_access_bytes',v_beta_bytes,'included_access_until',v_beta_until);
end;
$$;

-- Existing grants are retained explicitly; trusted Apple verification remains
-- the only source of paid entitlements. New internal helpers are not public APIs.
revoke all on function public.apply_verified_family_subscription(jsonb,uuid,uuid,text,text),
 public.apply_verified_family_subscription_internal(jsonb,uuid,uuid,text,text),
 public.prepare_verified_apple_repurchase(jsonb,uuid,uuid) from public,anon,authenticated;
grant execute on function public.apply_verified_family_subscription(jsonb,uuid,uuid,text,text),
 public.prepare_verified_apple_repurchase(jsonb,uuid,uuid) to service_role;

revoke all on all functions in schema heiro_billing from public,anon,authenticated;
