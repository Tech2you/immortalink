-- An Apple notification can beat client validation after an expired plan is
-- purchased for a new family. Keep the old binding unchanged until the verified
-- checkout is applied; a renewal must not silently reactivate the old family.
do $$ declare definition text; marker text := '    select * into v_epoch from public.apple_sponsor_reassignments'; begin
 definition:=pg_get_functiondef('public.apply_verified_family_subscription(jsonb,uuid,uuid,text,text)'::regprocedure);
 if position(marker in definition)=0 then raise exception 'Unexpected Apple purchase wrapper'; end if;
 execute replace(definition,marker,$patch$
    if p_source='server_notification' and not v_binding.retired
      and v_token=v_binding.purchaser_id::text and p_transaction->>'revocationDate' is null
      and coalesce(p_notification_type,'') not in ('REFUND','REVOKE')
      and exists(select 1 from public.apple_repurchase_checks c
        where c.original_transaction_id=v_original and c.user_id=v_binding.purchaser_id
        and c.family_id is distinct from v_binding.family_id and c.environment=v_env
        and c.binding_snapshot->'family_id' is not distinct from to_jsonb(v_binding)->'family_id'
        and c.binding_snapshot->'created_at' is not distinct from to_jsonb(v_binding)->'created_at'
        and v_binding.last_purchase_at<=c.last_purchase_at and v_purchase>c.expired_at
        and exists(select 1 from public.family_members m where m.family_id=c.family_id and m.user_id=c.user_id)
        and ((p_transaction->>'transactionReason'='PURCHASE' and v_purchase>c.checked_at and v_purchase<=c.valid_until
          and exists(select 1 from public.family_sponsor_checkout_attempts a
            where a.family_id=c.family_id and a.user_id=c.user_id and a.reserved_at>=c.checked_at
            and v_purchase>=a.reserved_at and v_purchase<=least(a.expires_at,coalesce(a.released_at,a.expires_at))))
          or exists(select 1 from public.apple_sponsorship_conflicts x
            where x.original_transaction_id=v_original and x.environment=v_env
            and x.reason='APPLE_REPURCHASE_AWAITING_CLIENT' and x.first_seen_at>=c.checked_at))) then
      return public.record_apple_sponsorship_conflict(p_transaction,'APPLE_REPURCHASE_AWAITING_CLIENT',v_binding.family_id,v_binding.purchaser_id);
    end if;
$patch$||marker);
end $$;

-- Service-only, after current Apple transaction AND renewal verification.
-- Acknowledges service already delivered to the payer's previous family. Never
-- changes its destination or quotas. Release only a hold proven fulfilled by a
-- recorded PURCHASE in that exact checkout window, never an unrelated attempt.
create function public.acknowledge_owned_apple_contribution(p_transaction jsonb,p_user_id uuid,p_family_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 o text:=p_transaction->>'originalTransactionId'; env text:=lower(p_transaction->>'environment');
 expiry timestamptz:=to_timestamp((p_transaction->>'expiresDate')::numeric/1000);
 purchased timestamptz:=to_timestamp((p_transaction->>'purchaseDate')::numeric/1000);
 signed timestamptz:=to_timestamp((p_transaction->>'signedDate')::numeric/1000);
 b public.apple_sponsor_bindings%rowtype; e jsonb; f uuid; r public.family_sponsor_reservations%rowtype; resolved uuid;
begin
 if p_user_id is null or o is null or env is null or env not in ('production','sandbox')
  or p_transaction->>'bundleId' is distinct from 'com.everroots.app'
  or lower(p_transaction->>'appAccountToken') is distinct from p_user_id::text
  or nullif(p_transaction->>'transactionId','') is null
  or expiry is null or expiry<=now() or purchased is null or purchased>=expiry
  or signed is null or signed>now()+interval '1 minute'
  or p_transaction->>'revocationDate' is not null then raise exception 'APPLE_MOVE_UNAVAILABLE'; end if;
 perform pg_advisory_xact_lock(hashtext('apple:'||o));
 perform pg_advisory_xact_lock(hashtext('sponsor-user:'||p_user_id));
 select * into b from public.apple_sponsor_bindings where original_transaction_id=o;
 if not found or b.retired or b.purchaser_id is distinct from p_user_id or b.environment is distinct from env
  or b.family_id=p_family_id then raise exception 'APPLE_MOVE_UNAVAILABLE'; end if;
 for f in select distinct id from unnest(array[b.family_id,p_family_id]) id where id is not null order by id loop
  perform pg_advisory_xact_lock(hashtext(f::text));
 end loop;
 select * into b from public.apple_sponsor_bindings where original_transaction_id=o;
 if b.retired or b.purchaser_id is distinct from p_user_id or b.family_id=p_family_id
  or not exists(select 1 from public.family_members where family_id=p_family_id and user_id=p_user_id) then
  raise exception 'FAMILY_MEMBERSHIP_REQUIRED'; end if;
 select to_jsonb(t) into e from public.family_entitlements t where apple_original_transaction_id=o;
 if e is null and b.family_id is null then
  select entitlement into e from heiro_billing.detached_contributions where original_id=o and purchaser_id=p_user_id;
 end if;
 if e is null or e->>'status'<>'active' or e->>'apple_product_id' is distinct from p_transaction->>'productId'
  or (e->>'current_period_end')::timestamptz is distinct from expiry
  or purchased is distinct from b.last_purchase_at or signed<b.last_signed_at
  or (e->>'billing_owner_user_id')::uuid is distinct from p_user_id then raise exception 'APPLE_MOVE_UNAVAILABLE'; end if;
 select * into r from public.family_sponsor_reservations where family_id=p_family_id and user_id=p_user_id;
 if found and exists(select 1 from public.apple_subscription_events v
   join public.apple_repurchase_checks c on c.original_transaction_id=v.apple_original_transaction_id
   where v.apple_original_transaction_id=o and v.apple_environment=env and v.entitlement_status='active'
    and v.raw_payload->>'transactionReason'='PURCHASE' and lower(v.raw_payload->>'appAccountToken')=p_user_id::text
    and v.raw_payload->>'revocationDate' is null and c.user_id=p_user_id and c.family_id=p_family_id
    and c.environment=env and c.checked_at<=r.reserved_at and c.expired_at<r.reserved_at
    and to_timestamp((v.raw_payload->>'purchaseDate')::numeric/1000)<=c.valid_until
    and to_timestamp((v.raw_payload->>'purchaseDate')::numeric/1000) between r.reserved_at and r.expires_at
    and exists(select 1 from public.family_sponsor_checkout_attempts a where a.reservation_id=r.reservation_id
      and a.user_id=p_user_id and a.family_id=p_family_id and a.released_at is null)) then
  resolved:=r.reservation_id;
  update public.family_sponsor_checkout_attempts set released_at=now() where reservation_id=r.reservation_id;
  delete from public.family_sponsor_reservations where reservation_id=r.reservation_id and user_id=p_user_id and family_id=p_family_id;
 end if;
 return jsonb_build_object('code','APPLE_OWNED_PREVIOUS_CONTRIBUTION','status','active','paid_until',expiry,'resolved_reservation_id',resolved);
end $$;
revoke all on function public.acknowledge_owned_apple_contribution(jsonb,uuid,uuid) from public,anon,authenticated;
grant execute on function public.acknowledge_owned_apple_contribution(jsonb,uuid,uuid) to service_role;
