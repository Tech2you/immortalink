-- Sandbox purchases must never replace real production coverage, even after
-- expiry. The existing purchaser, reservation and replay protections stay intact.
alter function public.apply_verified_family_subscription(jsonb,uuid,uuid,text,text)
  rename to apply_verified_family_subscription_internal;
revoke all on function public.apply_verified_family_subscription_internal(jsonb,uuid,uuid,text,text)
  from public,anon,authenticated,service_role;

create function public.apply_verified_family_subscription(
  p_transaction jsonb,p_family_id uuid,p_user_id uuid,p_source text,
  p_notification_type text default null
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_original text := nullif(p_transaction->>'originalTransactionId','');
  v_family uuid;
begin
  -- Keep lock order identical to the underlying verifier/apply transaction.
  if v_original is not null then
    perform pg_advisory_xact_lock(hashtext('apple:' || v_original));
    select family_id into v_family from public.apple_sponsor_bindings
      where original_transaction_id=v_original;
  end if;
  v_family := coalesce(v_family,p_family_id);
  if v_family is not null then
    perform pg_advisory_xact_lock(hashtext(v_family::text));
    if lower(p_transaction->>'environment')='sandbox' and exists (
      select 1 from public.family_entitlements
      where family_id=v_family and apple_environment='production'
    ) then
      raise exception 'APPLE_ENVIRONMENT_MISMATCH';
    end if;
  end if;
  return public.apply_verified_family_subscription_internal(
    p_transaction,p_family_id,p_user_id,p_source,p_notification_type);
end;
$$;
revoke all on function public.apply_verified_family_subscription(jsonb,uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.apply_verified_family_subscription(jsonb,uuid,uuid,text,text) to service_role;
