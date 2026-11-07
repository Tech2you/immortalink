-- Compatibility and bounded processing for the launch text/photo checker.
-- Defaults remain OFF. No existing memory is scanned by this migration.
-- Requires all staged screening migrations through delivery_outboxes.
-- Limits match the app's 20-photo flow and existing 50,000-character stories.
-- Larger text is checked in code-point-safe pieces, never silently truncated.

alter table content_safety.screening_photo_tickets
  drop constraint screening_photo_tickets_image_index_check,
  add constraint screening_photo_tickets_image_index_check check(image_index between 0 and 19);
-- Permit one maximum-size 20-photo post without raising the global daily/monthly budgets.
update content_safety.screening_processing_limits set max_bytes=251658240 where scope='user_hour';


create or replace function public.get_content_screening_permission()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_policy constant text := 'openai-safety-text-photo-2026-11-05';
  v_result jsonb;
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  select pg_catalog.jsonb_build_object(
    'policy_version', v_policy,
    'allowed', p.allowed and p.policy_version = v_policy,
    'revision', p.revision::text
  ) into v_result
  from content_safety.screening_permissions p where p.user_id = v_user;
  return coalesce(v_result, pg_catalog.jsonb_build_object(
    'policy_version', v_policy, 'allowed', false, 'revision', '0'
  ));
end;
$$;

create or replace function public.set_content_screening_permission(
  p_allowed boolean, p_policy_version text, p_expected_user_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_policy constant text := 'openai-safety-text-photo-2026-11-05';
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  -- A dialog opened before an account switch must not grant the new account.
  if p_expected_user_id is distinct from v_user then
    raise exception 'Account changed; reopen permission settings' using errcode = '42501';
  end if;
  if p_allowed is null then
    raise exception 'Permission choice required' using errcode = '22023';
  end if;
  if p_allowed and p_policy_version is distinct from v_policy then
    raise exception 'Screening disclosure changed' using errcode = '22023';
  end if;
  -- Withdrawal must work even from an older disclosure. Every choice advances
  -- the epoch so a later opt-in cannot revive work claimed before withdrawal.
  insert into content_safety.screening_permissions as p
    (user_id, policy_version, allowed)
  values (v_user, v_policy, p_allowed)
  on conflict (user_id) do update set
    policy_version = excluded.policy_version,
    allowed = excluded.allowed,
    revision = p.revision + 1,
    updated_at = pg_catalog.now();
  return public.get_content_screening_permission();
end;
$$;

create or replace function content_safety.screening_permission_matches(
  p_user_id uuid, p_revision bigint
)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from content_safety.screening_permissions p
    where p.user_id = p_user_id and p.allowed
      and p.policy_version = 'openai-safety-text-photo-2026-11-05'
      and p.revision = p_revision
  );
$$;

create or replace function content_safety.screening_snapshot(p_kind text,p_target uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  c content_safety.screening_controls; origin content_safety.screening_origins;
  m jsonb; scope jsonb; actors uuid[]; permissions jsonb := '[]';
  refs jsonb := '[]'; objects jsonb := '[]'; all_objects jsonb := '[]'; text_input text;
  image_count integer:=0; checkable boolean;
  f uuid; v uuid; l uuid; a uuid; p content_safety.screening_permissions;
  r record; o storage.objects; n integer := 0; source jsonb;
begin
  select * into c from content_safety.screening_controls where singleton;
  if c.enabled is not true or c.eligible_after is null then
    return jsonb_build_object('code','SCREENING_DISABLED');
  end if;
  if p_kind='memory' then
    select * into origin from content_safety.screening_origins where memory_id=p_target;
  elsif p_kind='legacy_memory' then
    select * into origin from content_safety.screening_origins where legacy_memory_id=p_target;
  else return jsonb_build_object('code','UNSUPPORTED_TARGET');
  end if;
  if not found then return jsonb_build_object('code','ARCHIVE_EXCLUDED'); end if;
  if origin.requested_at is null then return jsonb_build_object('code','SHARING_REQUEST_REQUIRED'); end if;
  if p_kind='memory' then
    select to_jsonb(mm),vv.id,vv.family_id,array[vv.owner_id],
      jsonb_build_object('vault',vv.id,'owner',vv.owner_id,'primary_family',vv.family_id,'families',(
        select coalesce(jsonb_agg(fm.family_id order by fm.family_id),'[]')
        from public.family_members fm where fm.user_id=vv.owner_id))
      into m,v,f,actors,scope from public.memories mm
      join public.vaults vv on vv.id=mm.vault_id where mm.id=p_target;
    if v is distinct from origin.scope_id then return jsonb_build_object('code','SCOPE_CHANGED'); end if;
    -- This remains a sharing-intent check, not an assertion that feed=false is private.
    if m->>'share_to_family_feed' is distinct from 'true' then
      return jsonb_build_object('code','NOT_REQUESTED_FOR_SHARING');
    end if;
  else
    select to_jsonb(mm),ll.id,ll.family_id,array[mm.contributor_id,mm.last_editor_id],
      jsonb_build_object('legacy',ll.id,'family',ll.family_id)
      into m,l,f,actors,scope from public.legacy_memories mm
      join public.legacy_family_members ll on ll.id=mm.legacy_member_id
      where mm.id=p_target and mm.family_id=ll.family_id;
    if l is distinct from origin.scope_id then return jsonb_build_object('code','SCOPE_CHANGED'); end if;
  end if;
  if m is null then return jsonb_build_object('code','TARGET_UNAVAILABLE'); end if;
  if p_actor is null or not coalesce(p_actor=any(actors),false) then
    return jsonb_build_object('code','ACTOR_MISMATCH');
  end if;
  if f is null or not exists(select 1 from public.family_members
    where family_id=f and user_id=p_actor) then
    return jsonb_build_object('code','FAMILY_UNAVAILABLE');
  end if;
  if exists(select 1 from content_safety.restrictions rr where
    (rr.target_kind=p_kind and rr.target_id=p_target)
    or (rr.target_kind='vault' and rr.target_id=v)
    or (rr.target_kind='legacy_profile' and rr.target_id=l)
    or (rr.target_kind='family' and rr.target_id=f)) then
    return jsonb_build_object('code','RESTRICTED_TARGET');
  end if;
  if exists(select 1 from public.content_reports cr where cr.reason='sexual_content'
    and ((cr.target_kind=p_kind and cr.target_id=p_target)
      or (cr.target_kind='vault' and cr.target_id=v)
      or (cr.target_kind='legacy_profile' and cr.target_id=l)
      or (cr.target_kind='family' and cr.target_id=f))) then
    return jsonb_build_object('code','RESTRICTED_REVIEW_REQUIRED');
  end if;
  for r in select * from content_safety.memory_attachment_refs(p_kind,p_target)
    order by relation,row_id limit 65 loop
    n:=n+1;
    if n>64 then return jsonb_build_object('code','ATTACHMENT_LIMIT'); end if;
    if not r.scope_valid then return jsonb_build_object('code','ATTACHMENT_SCOPE_INVALID'); end if;
    select * into o from storage.objects where name=r.path and bucket_id=any(r.buckets);
    if not found or (select count(*) from storage.objects where name=r.path and bucket_id=any(r.buckets))<>1
      or not public.media_object_matches_scope(o.bucket_id,o.name,f,v,l,p_target) then
      return jsonb_build_object('code','ATTACHMENT_UNAVAILABLE');
    end if;
    checkable:=coalesce(o.metadata->>'mimetype','') in ('image/jpeg','image/png','image/webp')
      and r.relation in ('memory_photos','legacy_memory_photos');
    if not checkable then
      -- Explicit launch coverage: do not fetch, transcribe or send recordings or
      -- videos to OpenAI. Adding one never exempts accompanying text/photos.
      -- Require matching media suffix/type; unsupported image formats stay held.
      if not ((r.relation in ('memory_voice_notes','legacy_memory_voice_notes')
          and coalesce(o.metadata->>'mimetype','') in ('audio/mp4','audio/m4a','audio/x-m4a','audio/mpeg','audio/wav','audio/x-wav','audio/webm','audio/ogg','audio/aac')
          and lower(o.name) ~ '\.(m4a|mp3|wav|webm|ogg|aac)$')
        or (r.relation in ('memory_photos','legacy_memory_photos')
          and coalesce(o.metadata->>'mimetype','') in ('video/mp4','video/quicktime','video/webm')
          and lower(o.name) ~ '\.(mp4|mov|m4v|webm)$')) then
        return jsonb_build_object('code','MEDIA_REVIEW_REQUIRED');
      end if;
    else
      image_count:=image_count+1;
      if image_count>20 then return jsonb_build_object('code','ATTACHMENT_LIMIT'); end if;
      if coalesce(o.metadata->>'size','') !~ '^[0-9]{1,9}$' then
        return jsonb_build_object('code','ATTACHMENT_SIZE_INVALID');
      end if;
      if (o.metadata->>'size')::bigint not between 1 and 12582912 then
        return jsonb_build_object('code','ATTACHMENT_SIZE_INVALID');
      end if;
      if p_kind='legacy_memory' then
        select actors || array[mp.contributor_id,mp.last_editor_id] into actors
          from public.legacy_memory_photos mp where mp.id=r.row_id;
      end if;
      objects:=objects || jsonb_build_array(jsonb_build_object(
        'id',o.id,'bucket',o.bucket_id,'path',o.name,'updated_at',o.updated_at,'metadata',o.metadata));
    end if;
    refs:=refs || jsonb_build_array(to_jsonb(r));
    all_objects:=all_objects || jsonb_build_array(jsonb_build_object(
      'id',o.id,'bucket',o.bucket_id,'path',o.name,'updated_at',o.updated_at,'metadata',o.metadata));
  end loop;
  text_input:=concat_ws(E'\n',m->>'prompt_text',m->>'prompt',m->>'body',
    m->>'people',m->>'location',m->>'memory_date_label',m->>'mood');
  if char_length(text_input)>60000 then return jsonb_build_object('code','TEXT_LIMIT'); end if;
  if text_input !~ '[^[:space:]]' and n=0 then return jsonb_build_object('code','INPUT_EMPTY'); end if;
  if array_position(actors,null) is not null then
    return jsonb_build_object('code','ATTRIBUTION_UNAVAILABLE');
  end if;
  for a in select distinct u from unnest(actors) u order by u loop
    if not exists(select 1 from auth.users where id=a)
      or exists(select 1 from public.account_deletion_jobs where user_id=a)
      or not exists(select 1 from public.family_members where user_id=a and family_id=f) then
      return jsonb_build_object('code','CONTRIBUTOR_UNAVAILABLE');
    end if;
    if exists(select 1 from content_safety.restrictions where target_kind='member' and target_id=a)
      or exists(select 1 from public.content_reports where target_kind='member'
        and target_id=a and reason='sexual_content') then
      return jsonb_build_object('code','RESTRICTED_REVIEW_REQUIRED');
    end if;
    if text_input ~ '[^[:space:]]' or image_count>0 then
    select * into p from content_safety.screening_permissions where user_id=a for share;
    if not found or not p.allowed or p.policy_version<>'openai-safety-text-photo-2026-11-05' then
      return jsonb_build_object('code','PERMISSION_REQUIRED');
    end if;
    permissions:=permissions || jsonb_build_array(jsonb_build_object('user',a,'revision',p.revision::text));
    end if;
  end loop;
  source:=jsonb_build_object('target',m,'scope',scope,'refs',refs,'objects',all_objects,
    'permissions',permissions,'origin',origin.id);
  return jsonb_build_object('code','READY','revision',encode(sha256(convert_to(source::text,'UTF8')),'hex'),
    'text',text_input,'images',objects,'report_only',text_input !~ '[^[:space:]]' and image_count=0);
end;
$$;

create or replace function content_safety.prepare_content_screening(p_job uuid,p_lease uuid,p_authorize boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  c content_safety.screening_controls; j content_safety.screening_jobs; s jsonb;
  stamp timestamptz;
  day_window bigint; hour_window bigint;
  global_used integer; user_used integer; request_count integer;
  source_bytes bigint; image_count integer; output_bytes bigint;
  lim content_safety.screening_processing_limits;
  b content_safety.screening_processing_budgets;
  subject_key text; period_start timestamptz; budget_blocked boolean:=false;
  reset_at timestamptz; next_reset timestamptz;
begin
  perform content_safety.media_lifecycle_lock();
  select * into c from content_safety.screening_controls where singleton for update;
  select * into j from content_safety.screening_jobs where id=p_job for update;
  if not found or j.state<>'leased' or j.lease_token is distinct from p_lease
    or j.lease_until<=clock_timestamp() or j.dispatched or p_authorize is null then
    return jsonb_build_object('code','LEASE_UNAVAILABLE');
  end if;
  s:=content_safety.screening_snapshot(j.target_kind,j.target_id,j.actor_id);
  if s->>'code'<>'READY' or s->>'revision' is distinct from j.revision then
    update content_safety.screening_jobs set state='stale',code='SOURCE_CHANGED',
      lease_token=null,lease_until=null,updated_at=clock_timestamp() where id=j.id;
    return jsonb_build_object('code','SOURCE_CHANGED');
  end if;
  request_count:=case when s->>'report_only'='true' then 0 else greatest(1,ceil(char_length(s->>'text')/4000.0)::integer) end;
  stamp:=clock_timestamp();
  day_window:=floor(extract(epoch from stamp)/86400)::bigint;
  hour_window:=floor(extract(epoch from stamp)/3600)::bigint;
  select used into global_used from content_safety.screening_budgets
    where scope='global_day' and subject='all' and window_start=day_window;
  select used into user_used from content_safety.screening_budgets
    where scope='user_hour' and subject=j.actor_id::text and window_start=hour_window;

  -- Do not repeatedly decode photos while the downstream allowance is exhausted.
  -- Dispatch still reserves its own allowance atomically immediately before send.
  if request_count>c.max_daily_requests-coalesce(global_used,0) or request_count>c.max_user_hourly_requests-coalesce(user_used,0) then
    update content_safety.screening_jobs set state='queued',code='BUDGET_LIMIT',attempts=attempts-1,
      lease_token=null,lease_until=null,available_at=stamp+interval '1 hour',
      updated_at=stamp where id=j.id;
    return jsonb_build_object('code','BUDGET_LIMIT');
  end if;

  if j.processing_lease_token is distinct from j.lease_token then
    image_count:=jsonb_array_length(s->'images');
    select coalesce(sum((img->'metadata'->>'size')::bigint),0) into source_bytes
      from jsonb_array_elements(s->'images') img;
    -- Reserve one binary worker response AND provider base64 for each bounded
    -- 512 KiB JPEG, plus text escaping/wrappers. No refunds on failed attempts.
    output_bytes:=image_count::bigint*(524288+699052)+6::bigint*octet_length(s->>'text')+1024;
    if source_bytes>251658240 then
      update content_safety.screening_jobs set state='review',code='SOURCE_BATCH_TOO_LARGE',
        lease_token=null,lease_until=null,updated_at=stamp where id=j.id;
      return jsonb_build_object('code','SOURCE_BATCH_TOO_LARGE');
    end if;
    -- Missing limits are a configuration error, never unlimited capacity.
    if (select count(*) from content_safety.screening_processing_limits)<>3 then
      return jsonb_build_object('code','PROCESSING_LIMITS_UNAVAILABLE');
    end if;
    for lim in select * from content_safety.screening_processing_limits order by scope for share loop
      subject_key:=case when lim.scope='user_hour' then j.actor_id::text else 'all' end;
      period_start:=date_trunc(case lim.scope when 'global_month' then 'month'
        when 'global_day' then 'day' else 'hour' end,stamp at time zone 'UTC') at time zone 'UTC';
      next_reset:=case lim.scope when 'global_month' then
        ((period_start at time zone 'UTC')+interval '1 month') at time zone 'UTC'
        when 'global_day' then period_start+interval '24 hours' else period_start+interval '1 hour' end;
      select * into b from content_safety.screening_processing_budgets
        where scope=lim.scope and subject=subject_key and window_start=period_start;
      if source_bytes>lim.max_bytes-coalesce(b.used_bytes,0)
        or coalesce(b.used_jobs,0)>=lim.max_jobs
        or image_count>lim.max_images-coalesce(b.used_images,0)
        or output_bytes>lim.max_output_bytes-coalesce(b.used_output_bytes,0) then
        budget_blocked:=true; reset_at:=greatest(reset_at,next_reset);
      end if;
    end loop;
    if budget_blocked then
      update content_safety.screening_jobs set state='queued',code='PROCESSING_BUDGET_LIMIT',
        attempts=attempts-1,lease_token=null,lease_until=null,available_at=reset_at,updated_at=stamp where id=j.id;
      return jsonb_build_object('code','PROCESSING_BUDGET_LIMIT');
    end if;
    for lim in select * from content_safety.screening_processing_limits order by scope loop
      subject_key:=case when lim.scope='user_hour' then j.actor_id::text else 'all' end;
      period_start:=date_trunc(case lim.scope when 'global_month' then 'month'
        when 'global_day' then 'day' else 'hour' end,stamp at time zone 'UTC') at time zone 'UTC';
      insert into content_safety.screening_processing_budgets values
        (lim.scope,subject_key,period_start,source_bytes,1,image_count,output_bytes)
        on conflict(scope,subject) do update set window_start=excluded.window_start,
          used_bytes=case when screening_processing_budgets.window_start=excluded.window_start
            then screening_processing_budgets.used_bytes+excluded.used_bytes else excluded.used_bytes end,
          used_jobs=case when screening_processing_budgets.window_start=excluded.window_start
            then screening_processing_budgets.used_jobs+1 else 1 end,
          used_images=case when screening_processing_budgets.window_start=excluded.window_start
            then screening_processing_budgets.used_images+excluded.used_images else excluded.used_images end,
          used_output_bytes=case when screening_processing_budgets.window_start=excluded.window_start
            then screening_processing_budgets.used_output_bytes+excluded.used_output_bytes else excluded.used_output_bytes end;
    end loop;
    update content_safety.screening_jobs set processing_lease_token=lease_token,updated_at=stamp where id=j.id;
  end if;
  if not p_authorize then return s || jsonb_build_object('processing_reserved',true); end if;
  insert into content_safety.screening_budgets values('global_day','all',day_window,request_count)
    on conflict(scope,subject) do update set window_start=excluded.window_start,
      used=case when screening_budgets.window_start=excluded.window_start then screening_budgets.used+excluded.used else excluded.used end;
  insert into content_safety.screening_budgets values('user_hour',j.actor_id::text,hour_window,request_count)
    on conflict(scope,subject) do update set window_start=excluded.window_start,
      used=case when screening_budgets.window_start=excluded.window_start then screening_budgets.used+excluded.used else excluded.used end;
  update content_safety.screening_jobs set dispatched=true,code='DISPATCH_RESERVED',
    updated_at=stamp where id=j.id;
  return jsonb_build_object('code','DISPATCH_RESERVED','revision',j.revision,'requests_reserved',request_count);
end;
$$;

create or replace function public.claim_content_screening()
returns jsonb language plpgsql security definer set search_path='' as $$
declare c content_safety.screening_controls; j content_safety.screening_jobs; s jsonb; i integer;
begin
  perform content_safety.media_lifecycle_lock();
  select * into c from content_safety.screening_controls where singleton for update;
  if c.enabled is not true or c.eligible_after is null then return null; end if;
  for i in 1..20 loop
    select * into j from content_safety.screening_jobs
      where (state='queued' and available_at<=clock_timestamp())
         or (state='leased' and lease_until<=clock_timestamp())
      order by available_at,created_at,id limit 1 for update skip locked;
    if not found then return null; end if;
    s:=content_safety.screening_snapshot(j.target_kind,j.target_id,j.actor_id);
    if s->>'code'<>'READY' or s->>'revision' is distinct from j.revision then
      update content_safety.screening_jobs set state='stale',code='SOURCE_CHANGED',
        lease_token=null,lease_until=null,dispatched=false,updated_at=clock_timestamp() where id=j.id;
    elsif j.attempts>=3 or j.created_at<clock_timestamp()-interval '24 hours' then
      update content_safety.screening_jobs set state='review',code='RETRY_LIMIT',
        lease_token=null,lease_until=null,dispatched=false,updated_at=clock_timestamp() where id=j.id;
    else
      update content_safety.screening_jobs set state='leased',code='CLAIMED',attempts=attempts+1,
        lease_token=gen_random_uuid(),lease_until=clock_timestamp()+interval '6 minutes',
        dispatched=false,updated_at=clock_timestamp() where id=j.id returning * into j;
      -- No content in claim logs. Load with the exact lease using prepare below.
      return jsonb_build_object('id',j.id,'lease_token',j.lease_token,'revision',j.revision);
    end if;
  end loop;
  return null;
end;
$$;

create or replace function public.claim_content_screening_photo(p_job uuid,p_lease uuid,p_index integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s jsonb; t content_safety.screening_photo_tickets; until_at timestamptz;
begin
  if p_index is null or p_index not between 0 and 19 then
    return jsonb_build_object('code','PHOTO_UNAVAILABLE');
  end if;
  s:=content_safety.prepare_content_screening(p_job,p_lease,false);
  if s->>'code'<>'READY' then return jsonb_build_object('code',s->>'code'); end if;
  if p_index>=jsonb_array_length(s->'images') then return jsonb_build_object('code','PHOTO_UNAVAILABLE'); end if;
  select lease_until into until_at from content_safety.screening_jobs where id=p_job;
  -- At most twenty metadata rows per parent; old tickets cannot be replayed after
  -- replacement. No image copies exist to orphan or clean up after a crash.
  delete from content_safety.screening_photo_tickets where job_id=p_job and lease_token<>p_lease;
  insert into content_safety.screening_photo_tickets(job_id,image_index,lease_token,revision,source_id,expires_at)
    values(p_job,p_index,p_lease,s->>'revision',(s->'images'->p_index->>'id')::uuid,until_at)
    on conflict(job_id,image_index) do nothing returning * into t;
  if not found then return jsonb_build_object('code','PHOTO_ALREADY_CLAIMED'); end if;
  return jsonb_build_object('code','PHOTO_CLAIMED','ticket_id',t.id,'revision',t.revision,
    'image_index',p_index,'processing_reserved',true,'image',s->'images'->p_index);
end;
$$;

create or replace function public.finish_content_screening_photo(p_ticket uuid,p_bytes integer,p_sha256 text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t content_safety.screening_photo_tickets; s jsonb;
begin
  if p_bytes is null or p_bytes not between 1 and 524288 or p_sha256 is null
    or p_sha256 !~ '^[0-9a-f]{64}$' then return jsonb_build_object('code','PHOTO_INVALID'); end if;
  perform content_safety.media_lifecycle_lock();
  select * into t from content_safety.screening_photo_tickets where id=p_ticket;
  if not found or t.state<>'processing' or t.expires_at<=clock_timestamp() then
    return jsonb_build_object('code','PHOTO_UNAVAILABLE');
  end if;
  s:=content_safety.prepare_content_screening(t.job_id,t.lease_token,false);
  if s->>'code'<>'READY' or s->>'revision' is distinct from t.revision
    or (s->'images'->t.image_index->>'id')::uuid is distinct from t.source_id then
    return jsonb_build_object('code','SOURCE_CHANGED');
  end if;
  update content_safety.screening_photo_tickets set state='ready',output_bytes=p_bytes,output_sha256=p_sha256
    where id=p_ticket and state='processing';
  if not found then return jsonb_build_object('code','PHOTO_UNAVAILABLE'); end if;
  return jsonb_build_object('code','PHOTO_READY','revision',t.revision);
end;
$$;

create or replace function content_safety.screening_review_snapshot(p_case uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  r content_safety.screening_reviews; o content_safety.screening_origins;
  m jsonb; f uuid; scope uuid; authors uuid[]; v uuid; l uuid; ref record;
  obj storage.objects; media jsonb:='[]'; fields jsonb:='{}'; result jsonb;
  available boolean:=false; a uuid; n integer:=0;
begin
  select * into r from content_safety.screening_reviews where id=p_case;
  if not found then raise exception 'SAFETY_REPORT_NOT_FOUND'; end if;
  select * into o from content_safety.screening_origins where id=r.generation;
  if found and o.scope_id=r.scope_id and r.state<>'obsolete'
    and exists(select 1 from content_safety.screening_controls where enforce_publication) then
    if r.target_kind='memory' and o.memory_id=r.target_id then
      select to_jsonb(mm),vv.id,vv.family_id,array[vv.owner_id] into m,scope,f,authors
        from public.memories mm join public.vaults vv on vv.id=mm.vault_id
        where mm.id=r.target_id and mm.share_to_family_feed is true;
      v:=scope;
    elsif r.target_kind='legacy_memory' and o.legacy_memory_id=r.target_id then
      select to_jsonb(mm),ll.id,ll.family_id,array[mm.contributor_id,mm.last_editor_id] into m,scope,f,authors
        from public.legacy_memories mm join public.legacy_family_members ll on ll.id=mm.legacy_member_id
        where mm.id=r.target_id and mm.family_id=ll.family_id;
      l:=scope;
    end if;
    available:=m is not null and scope=r.scope_id and f=r.family_id and o.requested_at is not null;
  end if;
  if available then
    for ref in select * from content_safety.memory_attachment_refs(r.target_kind,r.target_id) order by relation,row_id limit 65 loop
      if ref.relation in ('memory_voice_notes','legacy_memory_voice_notes') then continue; end if;
      if exists(select 1 from storage.objects video_object where video_object.name=ref.path and video_object.bucket_id=any(ref.buckets)
        and coalesce(video_object.metadata->>'mimetype','') in ('video/mp4','video/quicktime','video/webm')
        and lower(video_object.name) ~ '\.(mp4|mov|m4v|webm)$') then continue; end if;
      n:=n+1;
      if n>20 or not ref.scope_valid or ref.relation not in ('memory_photos','legacy_memory_photos') then available:=false; exit; end if;
      select * into obj from storage.objects where name=ref.path and bucket_id=any(ref.buckets);
      if not found or (select count(*) from storage.objects where name=ref.path and bucket_id=any(ref.buckets))<>1
        or not public.media_object_matches_scope(obj.bucket_id,obj.name,f,v,l,r.target_id)
        or coalesce(obj.metadata->>'mimetype','') not in ('image/jpeg','image/png','image/webp')
        or coalesce(obj.metadata->>'size','') !~ '^[0-9]{1,9}$' then available:=false; exit; end if;
      if (obj.metadata->>'size')::bigint not between 1 and 12582912 then available:=false; exit; end if;
      if r.target_kind='legacy_memory' then
        select authors||array[p.contributor_id,p.last_editor_id] into authors from public.legacy_memory_photos p where p.id=ref.row_id;
      end if;
      media:=media||jsonb_build_array(jsonb_build_object('id',obj.id,'kind','image','bucket',obj.bucket_id,
        'path',obj.name,'stamp',obj.updated_at,'metadata',obj.metadata));
    end loop;
    if authors is null or array_position(authors,null) is not null then available:=false; end if;
    for a in select distinct u from unnest(authors) u loop
      if not exists(select 1 from auth.users where id=a)
        or not exists(select 1 from public.family_members where family_id=f and user_id=a)
        or exists(select 1 from public.account_deletion_jobs where user_id=a)
        or exists(select 1 from content_safety.restrictions where target_kind='member' and target_id=a)
        or exists(select 1 from public.content_reports where target_kind='member' and target_id=a and reason='sexual_content') then available:=false; end if;
    end loop;
    if exists(select 1 from content_safety.restrictions where
      (target_kind=r.target_kind and target_id=r.target_id) or (target_kind='vault' and target_id=v)
      or (target_kind='legacy_profile' and target_id=l) or (target_kind='family' and target_id=f))
      or exists(select 1 from public.content_reports where reason='sexual_content' and
        ((target_kind=r.target_kind and target_id=r.target_id) or (target_kind='vault' and target_id=v)
        or (target_kind='legacy_profile' and target_id=l) or (target_kind='family' and target_id=f))) then available:=false; end if;
  end if;
  if available then
    fields:=jsonb_strip_nulls(jsonb_build_object('Memory',m->>'body','Prompt',m->>'prompt_text','Additional prompt',m->>'prompt',
      'People',m->>'people','Location',m->>'location','Date',m->>'memory_date_label','Mood',m->>'mood'));
    if octet_length(fields::text)>384000 then available:=false; end if;
  end if;
  if not available then fields:='{}'; media:='[]'; m:=null; end if;
  result:=jsonb_build_object('report',jsonb_build_object('id',r.id,'kind',r.target_kind,'status',r.state,
    'reason',r.reason,'createdAt',r.created_at,'accountActionAvailable',false),
    'available',available,'fields',fields,'media',media,'scopeNote',
    'Only the held text and photos. Recordings and videos use the existing report process. Approval does not remove report restrictions or authorize AI processing.');
  return result||jsonb_build_object('revision',md5(result::text||r.generation::text||r.updated_at::text||coalesce(m::text,'')));
end;
$$;

-- CREATE OR REPLACE retains the restrictive existing privileges.
revoke all on function content_safety.prepare_content_screening(uuid,uuid,boolean),
  content_safety.screening_snapshot(text,uuid,uuid), content_safety.screening_review_snapshot(uuid)
  from public,anon,authenticated,service_role;



create or replace function public.get_content_sharing_status(p_kind text,p_target uuid,p_expected_user_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); c content_safety.screening_controls; o content_safety.screening_origins;
  j content_safety.screening_jobs; scope uuid; f uuid; intent boolean; s jsonb; state text; text_value text; ready_state text;
begin
  if u is null or p_expected_user_id is distinct from u then raise exception 'Account changed; reopen sharing' using errcode='42501'; end if;
  perform content_safety.media_lifecycle_lock();
  if not exists(select 1 from auth.users where id=u) or exists(select 1 from public.account_deletion_jobs where user_id=u) then
    return jsonb_build_object('state','unavailable','can_request',false); end if;
  if p_kind='memory' then
    select v.id,v.family_id,m.share_to_family_feed,concat_ws(E'\n',to_jsonb(m)->>'prompt_text',to_jsonb(m)->>'prompt',to_jsonb(m)->>'body',to_jsonb(m)->>'people',to_jsonb(m)->>'location',to_jsonb(m)->>'memory_date_label',to_jsonb(m)->>'mood') into scope,f,intent,text_value
      from public.memories m join public.vaults v on v.id=m.vault_id
      where m.id=p_target and v.owner_id=u and content_safety.memory_visible(m.id);
    select * into o from content_safety.screening_origins where memory_id=p_target;
  elsif p_kind='legacy_memory' then
    select l.id,l.family_id,true,concat_ws(E'\n',to_jsonb(m)->>'prompt_text',to_jsonb(m)->>'prompt',to_jsonb(m)->>'body',to_jsonb(m)->>'people',to_jsonb(m)->>'location',to_jsonb(m)->>'memory_date_label',to_jsonb(m)->>'mood') into scope,f,intent,text_value from public.legacy_memories m
      join public.legacy_family_members l on l.id=m.legacy_member_id and l.family_id=m.family_id
      where m.id=p_target and (m.contributor_id=u or m.last_editor_id=u) and content_safety.legacy_memory_visible(m.id);
    select * into o from content_safety.screening_origins where legacy_memory_id=p_target;
  end if;
  if scope is null or not exists(select 1 from public.family_members where family_id=f and user_id=u)
    or exists(select 1 from content_safety.restrictions where target_kind='family' and target_id=f) then
    return jsonb_build_object('state','unavailable','can_request',false); end if;
  select * into c from content_safety.screening_controls where singleton;
  if c.enforce_publication is not true then return jsonb_build_object('state','disabled','can_request',false); end if;
  if o.id is null then return jsonb_build_object('state','archive','can_request',false); end if;
  if o.scope_id is distinct from scope then return jsonb_build_object('state','unavailable','can_request',false); end if;
  if intent is not true then return jsonb_build_object('state','not_requested','can_request',false); end if;
  if o.cleared_generation=o.id then return jsonb_build_object('state','shared','can_request',false); end if;
  if exists(select 1 from content_safety.screening_reviews where generation=o.id) then
    return jsonb_build_object('state','held','can_request',false); end if;
  if c.enabled is not true then return jsonb_build_object('state','paused','can_request',false); end if;
  ready_state:=case when coalesce(text_value,'') !~ '[^[:space:]]' and not exists(
    select 1 from content_safety.memory_attachment_refs(p_kind,p_target) ref
    join storage.objects obj on obj.name=ref.path and obj.bucket_id=any(ref.buckets)
    where coalesce(obj.metadata->>'mimetype','') in ('image/jpeg','image/png','image/webp'))
    then 'ready_no_check' else 'ready' end;
  if o.requested_at is null then return jsonb_build_object('state',ready_state,'can_request',true); end if;
  s:=content_safety.screening_snapshot(p_kind,p_target,u);
  if s->>'code'<>'READY' then
    state:=case s->>'code' when 'PERMISSION_REQUIRED' then 'permission_required'
      when 'VOICE_REVIEW_REQUIRED' then 'unsupported' when 'MEDIA_REVIEW_REQUIRED' then 'unsupported'
      when 'ATTACHMENT_LIMIT' then 'input_limit' when 'ATTACHMENT_SIZE_INVALID' then 'input_limit'
      when 'TEXT_LIMIT' then 'input_limit' when 'INPUT_EMPTY' then 'input_limit'
      when 'RESTRICTED_REVIEW_REQUIRED' then 'held' else 'unavailable' end;
    return jsonb_build_object('state',state,'can_request',state='permission_required');
  end if;
  select * into j from content_safety.screening_jobs where target_kind=p_kind and target_id=p_target;
  if not found or j.revision is distinct from s->>'revision' then return jsonb_build_object('state',ready_state,'can_request',true); end if;
  state:=case j.state when 'queued' then 'queued' when 'leased' then 'checking' when 'review' then 'held' else 'unavailable' end;
  return jsonb_build_object('state',state,'can_request',false);
end;
$$;
