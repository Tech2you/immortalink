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
 o text:='heiro-move-canary:'||gen_random_uuid(); t jsonb; reservation jsonb; q jsonb; r jsonb;
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
 insert into public.everroot_ai_usage_periods(scope_type,scope_id,period_start,used_count) values('family',f,public.everroot_period_start(),125),('family',g,public.everroot_period_start(),12);
 insert into public.everroot_transcription_usage_periods(scope_type,scope_id,period_start,used_seconds) values('family',f,public.everroot_period_start(),1800),('family',g,public.everroot_period_start(),60);
 delete from public.family_members where family_id=f and user_id=a;
 insert into public.family_members(family_id,user_id,role) values(g,a,'member');
 select jsonb_agg(to_jsonb(v) order by v.id) into people from public.vaults v where owner_id in (a,b,c);
 select jsonb_agg(to_jsonb(m) order by m.family_id,m.user_id) into members from public.family_members m where user_id in (a,b,c);
 if public.get_family_sponsorship(g)->>'can_move_contribution'<>'true' then raise exception 'Payer offer missing'; end if;
 if has_function_privilege('authenticated','public.move_verified_apple_contribution(jsonb,uuid,uuid,uuid)','execute') or
    has_function_privilege('anon','public.get_apple_contribution_move_candidate(uuid,uuid,uuid)','execute') then raise exception 'Move RPC exposed'; end if;
 q:=public.move_verified_apple_contribution(t,a,g,null);
 if (q->>'ai_remaining')::integer<>375 or (q->>'transcription_seconds_remaining')::integer<>5400 then raise exception 'Incorrect remaining allowance'; end if;
 if public.everroot_family_plan(g)<>'free' then raise exception 'Preview changed benefits'; end if;
 begin
  perform public.move_verified_apple_contribution(t,c,g,(q->>'confirmation_id')::uuid);
 exception when others then
  if sqlerrm<>'APPLE_MOVE_UNAVAILABLE' then raise; end if; denied:=true;
 end;
 if not denied then raise exception 'Foreign payer was allowed'; end if;
 r:=public.move_verified_apple_contribution(t,a,g,(q->>'confirmation_id')::uuid);
 if r->>'moved'<>'true' or public.everroot_family_plan(f)<>'free' or (public.everroot_limits(g)->>'storage_bytes')::bigint<>5368709120 then raise exception 'Grant did not move exactly once'; end if;
 perform public.move_verified_apple_contribution(t,a,g,(q->>'confirmation_id')::uuid);
 if (select used_count from public.everroot_ai_usage_periods where scope_type='family' and scope_id=g and period_start=public.everroot_period_start())<>137 then raise exception 'Usage lost or duplicated'; end if;
 if (select used_seconds from public.everroot_transcription_usage_periods where scope_type='family' and scope_id=g and period_start=public.everroot_period_start())<>1860 then raise exception 'Transcription usage lost'; end if;
 if (select jsonb_agg(to_jsonb(v) order by v.id) from public.vaults v where owner_id in (a,b,c)) is distinct from people then raise exception 'Vaults changed'; end if;
 if (select jsonb_agg(to_jsonb(m) order by m.family_id,m.user_id) from public.family_members m where user_id in (a,b,c)) is distinct from members then raise exception 'Membership changed'; end if;
 perform public.everroot_consume_ai_usage(g,null,1);
 -- A later deletion of the old tree must not erase the payer's remaining grant.
 delete from public.family_groups where id=g;
 insert into public.family_members(family_id,user_id,role) values(f,a,'member');
 q:=public.move_verified_apple_contribution(t,a,f,null);
 if (q->>'previous_family_exists')::boolean or (q->>'ai_remaining')::integer<>362 then raise exception 'Detached billing/usage not preserved'; end if;
 perform public.move_verified_apple_contribution(t,a,f,(q->>'confirmation_id')::uuid);
 if (select used_count from public.everroot_ai_usage_periods where scope_type='family' and scope_id=f and period_start=public.everroot_period_start())<>138 then raise exception 'Detached usage reset'; end if;
end $$;
rollback;
select 'passed; all disposable test data rolled back' as contribution_move_canary,
 (select count(*) from public.apple_sponsor_bindings where original_transaction_id like 'heiro-move-canary:%') as remaining_test_bindings;
