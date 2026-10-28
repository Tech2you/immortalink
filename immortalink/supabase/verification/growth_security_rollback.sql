-- Approved disposable fixtures only. No email, provider request or stored file.
begin;
set local statement_timeout='20s';
set local lock_timeout='3s';
do $$
declare
  a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); f uuid:=gen_random_uuid();
  v uuid:=gen_random_uuid(); m uuid:=gen_random_uuid(); invite uuid; fresh uuid;
  response jsonb; details text; i integer;
begin
  insert into auth.users(id) values(a),(b);
  insert into public.family_groups(id,name,created_by) values(f,'Disposable security QA',a);
  insert into public.family_members(family_id,user_id,role) values(f,a,'owner'),(f,b,'member');
  insert into public.vaults(id,owner_id,family_id,name) values(v,a,f,'Disposable QA vault');
  insert into public.memories(id,vault_id,life_stage,prompt_key,prompt_text,body)
    values(m,v,'early','security-qa','QA','<script>inert QA text</script>');

  perform set_config('request.jwt.claim.sub',b::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin
    update public.memory_chunks set chunk_text='forbidden' where memory_id=m;
    raise exception 'QA index mutation unexpectedly allowed';
  exception when insufficient_privilege then null; end;
  begin
    perform public.claim_family_notification('memory_added',m,a);
    raise exception 'QA client could impersonate notification actor';
  exception when insufficient_privilege then null; end;
  execute 'set local role postgres';
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
  response:=public.claim_family_notification('memory_added',m,a);
  if response->'allowed' is distinct from 'true'::jsonb or response->'recipient_ids' is distinct from jsonb_build_array(b) then
    raise exception 'QA authorized notification failed: %',response;
  end if;
  if public.claim_family_notification('memory_added',m,a)->>'code'<>'DUPLICATE' then
    raise exception 'QA repeated notification not blocked'; end if;
  if public.claim_family_notification('memory_added',m,b)->>'code'<>'DENIED' then
    raise exception 'QA other author notification not blocked'; end if;
  insert into notification_guard.claims(event_key,family_id,actor_id,claimed_at)
    select 'qa-'||gen_random_uuid()::text,f,a,clock_timestamp() from generate_series(1,19);
  if public.claim_family_notification('family_joined',f,a)->>'code'<>'RATE_LIMIT' then
    raise exception 'QA notification sender cap failed'; end if;

  if public.everroot_limits(f)->'real_members' is distinct from 'null'::jsonb
    or public.everroot_limits(f)->'invites_monthly' is distinct from 'null'::jsonb
    or public.everroot_limit_int(f,'invites_hourly_per_member')<>20
    or public.everroot_limit_int(f,'invites_hourly_per_family')<>50 then
    raise exception 'QA growth limits mismatch'; end if;
  for i in 1..35 loop
    insert into public.family_members(family_id,user_id,role) values(f,gen_random_uuid(),'member');
  end loop;
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  for i in 1..8 loop
    insert into public.legacy_family_members(family_id,name,created_by) values(f,'Disposable QA',a);
  end loop;
  begin
    insert into public.legacy_family_members(family_id,name,created_by) values(f,'Excess QA',a);
    raise exception 'QA legacy cap failed';
  exception when others then
    get stacked diagnostics details=pg_exception_detail;
    if details is distinct from 'ERR_EVERROOT_LEGACY_LIMIT' then raise; end if;
  end;
  for i in 1..20 loop
    insert into public.family_invites(family_id,created_by,invite_code,expires_at)
      values(f,a,gen_random_uuid()::text,now()+interval '1 day') returning id into invite;
    delete from public.family_invites where id=invite;
    update family_access.invite_rate_events set created_at=clock_timestamp()-interval '1 minute' where family_id=f;
  end loop;
  begin
    insert into public.family_invites(family_id,created_by,invite_code) values(f,a,gen_random_uuid()::text);
    raise exception 'QA invite sender cap failed';
  exception when others then
    get stacked diagnostics details=pg_exception_detail;
    if details is distinct from 'ERR_EVERROOT_INVITE_RATE_LIMIT' then raise; end if;
  end;
  -- A metadata-only object inside this rolled-back transaction simulates full
  -- storage; no real media bytes or Storage API object is created or removed.
  for i in 1..50 loop
    insert into storage.objects(bucket_id,name,metadata)
      values('memory_photos',a::text||'/'||v::text||'/qa-'||i||'.jpg',jsonb_build_object('size',10485760,'mimetype','image/jpeg'));
  end loop;
  if public.everroot_storage_bytes_used(f,null)<>524288000 then raise exception 'QA storage fixture not counted'; end if;
  begin
    insert into public.family_members(family_id,user_id,role) values(f,gen_random_uuid(),'member');
    raise exception 'QA full storage allowed admission';
  exception when others then
    get stacked diagnostics details=pg_exception_detail;
    if details is distinct from 'ERR_EVERROOT_STORAGE_LIMIT' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
  begin
    insert into public.family_invites(family_id,created_by,invite_code) values(f,b,gen_random_uuid()::text);
    raise exception 'QA full storage allowed invitation';
  exception when others then
    get stacked diagnostics details=pg_exception_detail;
    if details is distinct from 'ERR_EVERROOT_STORAGE_LIMIT' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.rename_family(f,'Still accessible QA');
  execute 'set local role postgres';
  if (select name from public.family_groups where id=f)<>'Still accessible QA' then raise exception 'QA existing access failed'; end if;
end;
$$;
rollback;
select 'passed; all disposable records rolled back; no provider calls' as verification;
