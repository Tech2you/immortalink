-- Temporary beta access is not a paid Apple subscription. Preserve its allowance
-- without blocking a real contribution or an expired-purchase recovery.
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
  if exists(select 1 from public.family_entitlements where billing_owner_user_id=v_user and provider='apple'
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
      provider='apple' and (billing_owner_user_id=p_user_id or apple_original_transaction_id=v_original) and
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
          provider='apple' and (billing_owner_user_id=p_user_id or apple_original_transaction_id=v_original) and
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

