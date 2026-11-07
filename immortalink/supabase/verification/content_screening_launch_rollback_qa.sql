-- Database-only synthetic fixtures. No media bytes or provider requests.
-- All control changes, test accounts and metadata are rolled back together.
-- Dispatcher and delivery switches remain OFF throughout this transaction.
begin;
set local statement_timeout='30s';
set local lock_timeout='3s';
do $$
declare
  u uuid:=gen_random_uuid(); viewer uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  f uuid:=gen_random_uuid(); v uuid:=gen_random_uuid(); m uuid:=gen_random_uuid();
  archive uuid:=gen_random_uuid(); voice uuid:=gen_random_uuid(); p text;
  result jsonb; job jsonb; source jsonb; ticket jsonb; i integer;
begin
  if exists(select 1 from content_safety.screening_controls where enabled or enforce_publication or eligible_after is not null)
    or exists(select 1 from content_safety.screening_worker_config where enabled)
    or exists(select 1 from content_safety.screening_jobs) then
    raise exception 'QA requires the untouched disabled installation';
  end if;
  insert into auth.users(id) values(u),(viewer),(outsider);
  insert into public.family_groups(id,name,created_by) values(f,'Screening rollback QA',u);
  insert into public.family_members(family_id,user_id,role) values(f,u,'owner'),(f,viewer,'member');
  insert into public.vaults(id,owner_id,family_id,name) values(v,u,f,'Screening rollback QA');
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  insert into public.memories(id,vault_id,life_stage,prompt_key,prompt_text,body,share_to_family_feed)
    values(archive,v,'mid','rollback_archive','QA','Existing archive',true);
  execute 'reset role';
  if exists(select 1 from content_safety.screening_origins where memory_id=archive) then
    raise exception 'Disabled install captured an archive'; end if;
  update content_safety.screening_controls set enabled=true,enforce_publication=true,eligible_after=clock_timestamp();

  execute 'set local role authenticated';
  insert into public.memories(id,vault_id,life_stage,prompt_key,prompt_text,body,share_to_family_feed)
    values(m,v,'mid','rollback_mixed','QA','Harmless synthetic story',true),
      (voice,v,'mid','rollback_voice','','',true);
  begin
    perform public.claim_content_screening();
    raise exception 'An app user could claim processing work';
  exception when insufficient_privilege then null; end;
  begin
    perform public.dispatch_content_screening();
    raise exception 'An app user could dispatch work';
  exception when insufficient_privilege then null; end;
  begin
    perform 1 from content_safety.screening_jobs;
    raise exception 'An app user could inspect the private queue';
  exception when insufficient_privilege then null; end;
  result:=public.request_content_screening('memory',m,u);
  if result->>'code' is distinct from 'PERMISSION_REQUIRED' then
    raise exception 'Permission was not required: %',result; end if;
  result:=public.set_content_screening_permission(true,'openai-safety-text-photo-2026-11-05',u);
  if result->>'allowed' is distinct from 'true' then raise exception 'Consent failed'; end if;
  execute 'reset role';

  -- Metadata represents generated fixtures only. No file is uploaded or read.
  for i in 0..19 loop
    p:=u::text||'/'||v::text||'/memories/'||m::text||'/photo-'||i||'.png';
    insert into storage.objects(bucket_id,name,owner,owner_id,metadata)
      values('vault_photos',p,u,u::text,jsonb_build_object('size',100,'mimetype','image/png','eTag',repeat('a',32)));
    insert into public.memory_photos(vault_id,memory_id,path) values(v,m,p);
  end loop;
  foreach p in array array[
    u::text||'/'||v::text||'/memories/'||m::text||'/voice.m4a',
    u::text||'/'||v::text||'/memories/'||voice::text||'/voice.m4a'] loop
    insert into storage.objects(bucket_id,name,owner,owner_id,metadata)
      values('memory_voice',p,u,u::text,jsonb_build_object('size',100,'mimetype','audio/mp4','eTag',repeat('b',32)));
    insert into public.memory_voice_notes(vault_id,memory_id,path)
      values(v,(string_to_array(p,'/'))[4]::uuid,p);
  end loop;
  execute 'set local role authenticated';
  result:=public.request_content_screening('memory',m,u);
  if result->>'state' is distinct from 'queued' then raise exception 'Mixed queue failed: %',result; end if;
  if not exists(select 1 from public.memories where id=m) then raise exception 'Owner lost pending memory'; end if;
  perform set_config('request.jwt.claim.sub',viewer::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer,'role','authenticated')::text,true);
  if exists(select 1 from public.memories where id=m) then raise exception 'Pending memory leaked'; end if;
  if not exists(select 1 from public.memories where id=archive) then raise exception 'Archive disappeared'; end if;
  if exists(select 1 from storage.objects where name like u::text||'/'||v::text||'/memories/'||m::text||'/%') then
    raise exception 'Pending media leaked'; end if;
  result:=public.request_content_screening('memory',m,viewer);
  if result->>'code' is distinct from 'REQUEST_UNAVAILABLE' then
    raise exception 'Another member could authorize this memory'; end if;

  execute 'reset role';
  execute 'set local role service_role';
  job:=public.claim_content_screening();
  source:=public.prepare_content_screening((job->>'id')::uuid,(job->>'lease_token')::uuid,false);
  if source->>'code' is distinct from 'READY' or jsonb_array_length(source->'images')<>20
    or source->>'report_only' is distinct from 'false' then raise exception 'Mixed source incorrect: %',source->>'code'; end if;
  for i in 0..19 loop
    ticket:=public.claim_content_screening_photo((job->>'id')::uuid,(job->>'lease_token')::uuid,i);
    if ticket->>'code' is distinct from 'PHOTO_CLAIMED' then raise exception 'Photo claim failed: %',ticket; end if;
    result:=public.finish_content_screening_photo((ticket->>'ticket_id')::uuid,524289,repeat('a',64));
    if result->>'code' is distinct from 'PHOTO_INVALID' then raise exception 'Oversized photo accepted'; end if;
    result:=public.finish_content_screening_photo((ticket->>'ticket_id')::uuid,100,repeat('a',64));
    if result->>'code' is distinct from 'PHOTO_READY' then raise exception 'Photo result failed'; end if;
  end loop;
  result:=public.prepare_content_screening((job->>'id')::uuid,(job->>'lease_token')::uuid,true);
  if (result->>'requests_reserved')::integer<>20 then raise exception 'Missing per-photo request reservation: %',result; end if;
  result:=public.finish_content_screening((job->>'id')::uuid,(job->>'lease_token')::uuid,'clear');
  if result->>'state' is distinct from 'clear' then raise exception 'Synthetic finish failed: %',result; end if;
  execute 'reset role';
  execute 'set local role authenticated';
  if not exists(select 1 from public.memories where id=m) then raise exception 'Cleared memory not readable by family'; end if;
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
  if exists(select 1 from public.memories where id=m) then raise exception 'Cleared memory leaked outside family'; end if;
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);

  -- A material edit invalidates approval. Withdrawing permission invalidates
  -- an outstanding worker lease before it can fetch media.
  update public.memories set body='Changed synthetic story' where id=m;
  result:=public.request_content_screening('memory',m,u);
  if result->>'state' is distinct from 'queued' then raise exception 'Edited memory did not queue'; end if;
  execute 'reset role';
  execute 'set local role service_role';
  job:=public.claim_content_screening();
  execute 'reset role';
  execute 'set local role authenticated';
  perform public.set_content_screening_permission(false,'openai-safety-text-photo-2026-11-05',u);
  execute 'reset role';
  execute 'set local role service_role';
  result:=public.prepare_content_screening((job->>'id')::uuid,(job->>'lease_token')::uuid,false);
  if result->>'code' is distinct from 'SOURCE_CHANGED' then raise exception 'Withdrawal did not stop work: %',result; end if;
  execute 'reset role';

  -- Recordings without text/photos do not need OpenAI permission or a request.
  execute 'set local role authenticated';
  result:=public.get_content_sharing_status('memory',voice,u);
  if result->>'state' is distinct from 'ready_no_check' then raise exception 'Recording-only status incorrect: %',result; end if;
  result:=public.request_content_screening('memory',voice,u);
  if result->>'state' is distinct from 'queued' then raise exception 'Recording-only request failed'; end if;
  execute 'reset role';
  execute 'set local role service_role';
  job:=public.claim_content_screening();
  source:=public.prepare_content_screening((job->>'id')::uuid,(job->>'lease_token')::uuid,false);
  if source->>'report_only' is distinct from 'true' or jsonb_array_length(source->'images')<>0 then
    raise exception 'Recording would be sent for checking'; end if;
  result:=public.prepare_content_screening((job->>'id')::uuid,(job->>'lease_token')::uuid,true);
  if result->>'requests_reserved' is distinct from '0' then raise exception 'Recording charged a provider request'; end if;
  result:=public.finish_content_screening((job->>'id')::uuid,(job->>'lease_token')::uuid,'clear');
  if result->>'state' is distinct from 'clear' then raise exception 'Recording sharing failed'; end if;
  execute 'reset role';
  execute 'set local role authenticated';
  update public.memories set body='Edited archive' where id=archive;
  result:=public.request_content_screening('memory',archive,u);
  if result->>'code' is distinct from 'PERMISSION_REQUIRED' then raise exception 'Edited archive bypassed permission'; end if;
  execute 'reset role';
  if exists(select 1 from content_safety.screening_runs) then raise exception 'QA unexpectedly dispatched HTTP'; end if;
end $$;
rollback;
select 'PASS: disabled-install compatibility, private queue access, 20 photos with recording, bounded photo results, permission withdrawal, family isolation, recording-only zero-provider flow and archive edit; all test data rolled back' as result;
