-- Run only against the user's two nominated disposable accounts. All temporary
-- reservations and synthetic DB-layer entitlements roll back in a subtransaction.
-- This does not test Apple signatures, charge Apple, delete accounts or move media.
do $$
declare
  v_member uuid;
  v_other uuid;
  v_family uuid;
  v_tx jsonb;
  v_result jsonb;
  v_original text := 'rollback-preflight-' || gen_random_uuid()::text;
begin
  select id into strict v_member from auth.users where email='linebreakers@outlook.com';
  select id into strict v_other from auth.users where email='rossstrauss1@gmail.com';
  select a.family_id into strict v_family from public.family_members a
    join public.family_members b using(family_id)
    where a.user_id=v_member and b.user_id=v_other;
  if public.everroot_family_plan(v_family)<>'free' then
    raise exception 'Do not run synthetic preflight after a real test purchase';
  end if;
  begin
    perform set_config('request.jwt.claim.sub',v_member::text,true);
    perform public.reserve_family_sponsorship(v_family);
    perform set_config('request.jwt.claim.sub',v_other::text,true);
    begin
      perform public.reserve_family_sponsorship(v_family);
      raise exception 'FAIL: competing reservation accepted';
    exception when others then
      if sqlerrm<>'SPONSOR_PURCHASE_IN_PROGRESS' then raise; end if;
    end;
    perform set_config('request.jwt.claim.sub',v_member::text,true);
    v_tx := jsonb_build_object('bundleId','com.everroots.app',
      'originalTransactionId',v_original,'transactionId',v_original,
      'productId','everroots.family.monthly','appAccountToken',v_member,
      'environment','Sandbox','purchaseDate',extract(epoch from now())*1000,
      'signedDate',extract(epoch from now())*1000,
      'expiresDate',extract(epoch from now()+interval '1 day')*1000);
    v_result := public.apply_verified_family_subscription(v_tx,v_family,v_member,'client_validation');
    if v_result->>'applied'<>'true' or public.everroot_family_plan(v_family)<>'everroot_family' then
      raise exception 'FAIL: ordinary member sponsorship did not apply';
    end if;
    if not exists(select 1 from public.family_members where family_id=v_family and user_id=v_member and role='member') then
      raise exception 'FAIL: sponsorship changed the tree role';
    end if;
    begin
      perform public.apply_verified_family_subscription(v_tx,v_family,v_other,'client_validation');
      raise exception 'FAIL: other app account claimed purchase';
    exception when others then
      if sqlerrm<>'APPLE_PURCHASE_ALREADY_BOUND' then raise; end if;
    end;
    perform public.everroot_assert_usage_burst('ai',6);
    begin
      perform public.everroot_assert_usage_burst('ai',1);
      raise exception 'FAIL: burst allowance exceeded';
    exception when others then
      if sqlerrm<>'Please wait a minute before requesting more AI or transcription.' then raise; end if;
    end;
    raise exception 'Discard all synthetic test changes' using errcode='ZX001';
  exception when sqlstate 'ZX001' then null;
  end;
  if exists(select 1 from public.apple_sponsor_bindings where original_transaction_id=v_original)
    or exists(select 1 from public.apple_subscription_events where apple_original_transaction_id=v_original) then
    raise exception 'FAIL: test data persisted';
  end if;
  if public.everroot_family_plan(v_family)<>'free' then raise exception 'FAIL: test entitlement persisted'; end if;
end;
$$;
select 'PASS: member checkout, competing checkout blocked, purchaser binding, unchanged tree role, burst guard; all temporary writes rolled back' as result;
