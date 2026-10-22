-- A replaced sponsor may explicitly purchase again after the current coverage
-- ends. Restores and automatic renewals never transfer sponsorship on their own.
alter table public.apple_sponsor_bindings add column retired_at timestamptz;
update public.apple_sponsor_bindings set retired_at=now() where retired;

create or replace function public.apply_verified_family_subscription(
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
    if v_token is not null and v_token <> p_user_id::text then
      raise exception 'APPLE_PURCHASER_MISMATCH';
    end if;
    if not v_bound and (v_token is null or
        not public.has_family_sponsorship_attempt(v_family,p_user_id,v_purchase)) then
      return public.record_apple_sponsorship_conflict(p_transaction,'APPLE_PURCHASER_UNVERIFIED',v_family,p_user_id);
    end if;
  end if;
  select * into v_ent from public.family_entitlements where family_id=v_family for update;
  if v_ent.apple_original_transaction_id is distinct from v_original and
     v_ent.status in ('active','grace_period') and
     (v_ent.current_period_end is null or v_ent.current_period_end > now()) then
    return public.record_apple_sponsorship_conflict(p_transaction,'FAMILY_ALREADY_SPONSORED',v_family,p_user_id);
  end if;
  v_status := case when p_transaction->>'revocationDate' is not null or p_notification_type='REFUND' then 'refunded'
    when p_notification_type='REVOKE' then 'revoked'
    when v_end <= now() then 'expired' else 'active' end;
  if v_bound and v_binding.retired then
    -- History can clear the purchaser's preflight without modifying the family.
    if v_status='expired' then
      return jsonb_build_object('applied',true,'code','APPLE_RETIRED_HISTORY',
        'plan','free','status','expired','product_id',v_product,'current_period_end',v_end);
    end if;
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
    where family_id=v_family and original_transaction_id<>v_original and not retired;
  insert into public.family_entitlements(family_id,plan,status,provider,provider_entitlement_id,
    provider_subscription_id,billing_owner_user_id,current_period_end,apple_original_transaction_id,
    apple_product_id,apple_environment)
  values(v_family,case when v_status='active' then v_plan else 'free' end,v_status,'apple',v_tx,
    v_original,case when v_bound and not v_binding.retired then v_ent.billing_owner_user_id else p_user_id end,
    v_end,v_original,v_product,v_env)
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
