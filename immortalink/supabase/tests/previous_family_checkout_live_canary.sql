-- Execute only after the reviewed migration. No Apple/AI requests are made.
-- All users, families, transactions and counters below are disposable and the
-- entire transaction rolls back. Failure aborts the script before its proof row.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $$
declare
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
 f uuid:=gen_random_uuid(); g uuid:=gen_random_uuid();
 o text:='heiro-restore-canary:'||gen_random_uuid(); t jsonb; reservation jsonb; q jsonb; r jsonb;
 people jsonb; members jsonb; result jsonb; denied boolean:=false;
begin
 insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data) values
 (a,'authenticated','authenticated','{}','{}'),(b,'authenticated','authenticated','{}','{}'),(c,'authenticated','authenticated','{}','{}');
 insert into public.vaults(owner_id,name) values(a,'Move check A'),(b,'Move check B'),(c,'Move check C');
 insert into public.family_groups(id,name,created_by) values(f,'Move check source',b),(g,'Move check destination',c);
 insert into public.family_members(family_id,user_id,role) values(f,b,'owner'),(f,a,'member'),(g,c,'owner');
 perform set_config('request.jwt.claim.sub',a::text,true);
 reservation:=public.begin_family_storage_contribution(f);
 t:=jsonb_build_object('bundleId','com.everroots.app','environment','Sandbox','originalTransactionId',o,'transactionId',o||':purchase',
  'productId','everroots.family.monthly','appAccountToken',a,'transactionReason','PURCHASE',
  'purchaseDate',floor(extract(epoch from now())*1000),'signedDate',floor(extract(epoch from now())*1000),
  'expiresDate',floor(extract(epoch from now()+interval '1 day')*1000));
 r:=public.apply_verified_family_subscription(t,f,a,'client_validation',null);
 if r->>'applied'<>'true' then raise exception 'Canary purchase setup failed'; end if;
 perform public.release_family_sponsorship(f,(reservation->>'reservation_id')::uuid);

 -- Reproduce time-separated expired history and a subsequent checkout.
 t:=t||jsonb_build_object('expiresDate',floor(extract(epoch from now()-interval '5 minutes')*1000),
  'purchaseDate',floor(extract(epoch from now()-interval '10 minutes')*1000));
 update public.apple_sponsor_bindings set last_purchase_at=to_timestamp((t->>'purchaseDate')::numeric/1000) where original_transaction_id=o;
 update public.family_entitlements set status='expired',current_period_end=now()-interval '5 minutes' where apple_original_transaction_id=o;
 delete from public.family_members where family_id=f and user_id=a;
 insert into public.family_members(family_id,user_id,role) values(g,a,'member');
 perform public.prepare_verified_apple_repurchase(t,g,a);
 update public.apple_repurchase_checks set checked_at=now()-interval '2 minutes',last_purchase_at=to_timestamp((t->>'purchaseDate')::numeric/1000) where original_transaction_id=o;
 update public.apple_sponsor_bindings set last_purchase_at=to_timestamp((t->>'purchaseDate')::numeric/1000) where original_transaction_id=o;
 reservation:=public.begin_family_storage_contribution(g);
 update public.family_sponsor_reservations set reserved_at=now()-interval '1 minute' where reservation_id=(reservation->>'reservation_id')::uuid;
 update public.family_sponsor_checkout_attempts set reserved_at=now()-interval '1 minute' where reservation_id=(reservation->>'reservation_id')::uuid;
 t:=t||jsonb_build_object('transactionId',o||':new','purchaseDate',floor(extract(epoch from now()-interval '10 seconds')*1000),
  'expiresDate',floor(extract(epoch from now()+interval '1 day')*1000));
 r:=public.apply_verified_family_subscription(t,null,null,'server_notification','SUBSCRIBED');
 if r->>'code'<>'APPLE_REPURCHASE_AWAITING_CLIENT' or public.everroot_family_plan(f)<>'free' then raise exception 'Notification reactivated old family'; end if;
 -- Reproduce already-delivered build-41 purchases using the previous handler.
 perform public.apply_verified_family_subscription_internal(t,null,null,'server_notification','SUBSCRIBED');
 r:=public.acknowledge_owned_apple_contribution(t,a,g);
 if r->>'resolved_reservation_id' is distinct from reservation->>'reservation_id' then raise exception 'Fulfilled checkout not recovered'; end if;
 if public.everroot_family_plan(g)<>'free' then raise exception 'Restore moved benefits without consent'; end if;
 if has_function_privilege('authenticated','public.acknowledge_owned_apple_contribution(jsonb,uuid,uuid)','execute') or
  has_function_privilege('anon','public.acknowledge_owned_apple_contribution(jsonb,uuid,uuid)','execute') then raise exception 'Recovery helper exposed'; end if;
 q:=public.move_verified_apple_contribution(t,a,g,null);
 if public.everroot_family_plan(g)<>'free' then raise exception 'Preview moved benefits'; end if;
 r:=public.move_verified_apple_contribution(t,a,g,(q->>'confirmation_id')::uuid);
 if r->>'moved'<>'true' or public.everroot_family_plan(f)<>'free' or (public.everroot_limits(g)->>'storage_bytes')::bigint<>5368709120 then raise exception 'Confirmed move failed'; end if;
end $$;
rollback;
select 'passed; all disposable data rolled back' as checkout_recovery_canary,
 (select count(*) from public.apple_sponsor_bindings where original_transaction_id like 'heiro-restore-canary:%') as remaining_test_bindings;
