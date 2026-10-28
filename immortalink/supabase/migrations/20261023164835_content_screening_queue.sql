-- Staged queue only: no upload hooks, read-policy changes, scheduler or HTTP.
-- Enabling this table is NOT sufficient to enable screening in the product.
create table content_safety.screening_controls (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  eligible_after timestamptz,
  max_pending integer not null default 1000 check (max_pending between 1 and 10000),
  max_user_pending integer not null default 20 check (max_user_pending between 1 and 100),
  max_daily_requests integer not null default 1000 check (max_daily_requests between 1 and 10000),
  max_user_hourly_requests integer not null default 20 check (max_user_hourly_requests between 1 and 100)
);
insert into content_safety.screening_controls(singleton) values(true);

create table content_safety.screening_jobs (
  id uuid primary key default gen_random_uuid(),
  target_kind text not null check (target_kind in ('memory','legacy_memory')),
  target_id uuid not null,
  actor_id uuid not null references auth.users(id) on delete cascade,
  revision text not null check (revision ~ '^[0-9a-f]{64}$'),
  state text not null check (state in ('queued','leased','clear','review','stale')),
  code text not null,
  attempts integer not null default 0 check (attempts between 0 and 3),
  lease_token uuid,
  lease_until timestamptz,
  dispatched boolean not null default false,
  available_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(target_kind,target_id),
  check ((state='leased') = (lease_token is not null and lease_until is not null))
);
create index screening_jobs_ready on content_safety.screening_jobs(available_at,created_at)
  where state in ('queued','leased');
create index screening_jobs_actor on content_safety.screening_jobs(actor_id,state);

-- Rolling counters, not content or provider-response logs. Daily/hourly resets
-- happen under the controls row lock and do not reset with a worker restart.
create table content_safety.screening_budgets (
  scope text not null check (scope in ('global_day','user_hour')),
  subject text not null,
  window_start bigint not null,
  used integer not null check (used >= 0),
  primary key(scope,subject)
);
alter table content_safety.screening_controls enable row level security;
alter table content_safety.screening_jobs enable row level security;
alter table content_safety.screening_budgets enable row level security;
revoke all on content_safety.screening_controls,content_safety.screening_jobs,
  content_safety.screening_budgets from public,anon,authenticated,service_role;

-- Called only while holding the existing media lifecycle lock. The private
-- snapshot binds actual rows, scoped objects, recipients and every contributor's
-- permission epoch. No client-supplied text, path, owner or hash is trusted.
create function content_safety.screening_snapshot(p_kind text,p_target uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  c content_safety.screening_controls;
  m jsonb; scope jsonb; actors uuid[]; permissions jsonb := '[]';
  refs jsonb := '[]'; objects jsonb := '[]'; text_input text;
  f uuid; v uuid; l uuid; a uuid; p content_safety.screening_permissions;
  r record; o storage.objects; n integer := 0;
  source jsonb; created timestamptz;
begin
  select * into c from content_safety.screening_controls where singleton;
  if c.enabled is not true or c.eligible_after is null then
    return jsonb_build_object('code','SCREENING_DISABLED');
  end if;
  if p_kind='memory' then
    select to_jsonb(mm),vv.id,vv.family_id,array[vv.owner_id],
      jsonb_build_object('vault',vv.id,'owner',vv.owner_id,'primary_family',vv.family_id,'families',(
        select coalesce(jsonb_agg(fm.family_id order by fm.family_id),'[]')
        from public.family_members fm where fm.user_id=vv.owner_id))
      into m,v,f,actors,scope from public.memories mm
      join public.vaults vv on vv.id=mm.vault_id where mm.id=p_target;
    -- This queue is only for an explicit new sharing request. Feed=false is
    -- not claimed to be a private ACL; existing reads are deliberately untouched.
    if m->>'share_to_family_feed' is distinct from 'true' then
      return jsonb_build_object('code','NOT_REQUESTED_FOR_SHARING');
    end if;
  elsif p_kind='legacy_memory' then
    select to_jsonb(mm),ll.id,ll.family_id,array[mm.contributor_id,mm.last_editor_id],
      jsonb_build_object('legacy',ll.id,'family',ll.family_id)
      into m,l,f,actors,scope from public.legacy_memories mm
      join public.legacy_family_members ll on ll.id=mm.legacy_member_id
      where mm.id=p_target and mm.family_id=ll.family_id;
  else return jsonb_build_object('code','UNSUPPORTED_TARGET');
  end if;
  if m is null then return jsonb_build_object('code','TARGET_UNAVAILABLE'); end if;
  created := nullif(m->>'created_at','')::timestamptz;
  if created is null or created<c.eligible_after then
    return jsonb_build_object('code','ARCHIVE_EXCLUDED');
  end if;
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
  -- Reported sexual content is conservatively routed away from the provider,
  -- including dismissed reports: this queue cannot clear a suspicion itself.
  if exists(select 1 from public.content_reports cr where cr.reason='sexual_content'
    and ((cr.target_kind=p_kind and cr.target_id=p_target)
      or (cr.target_kind='vault' and cr.target_id=v)
      or (cr.target_kind='legacy_profile' and cr.target_id=l)
      or (cr.target_kind='family' and cr.target_id=f))) then
    return jsonb_build_object('code','RESTRICTED_REVIEW_REQUIRED');
  end if;
  for r in select * from content_safety.memory_attachment_refs(p_kind,p_target)
    order by relation,row_id limit 5 loop
    n:=n+1;
    if n>4 then return jsonb_build_object('code','ATTACHMENT_LIMIT'); end if;
    if r.relation in ('memory_voice_notes','legacy_memory_voice_notes') then
      return jsonb_build_object('code','VOICE_REVIEW_REQUIRED');
    end if;
    if not r.scope_valid then return jsonb_build_object('code','ATTACHMENT_SCOPE_INVALID'); end if;
    select * into o from storage.objects where name=r.path and bucket_id=any(r.buckets);
    if not found or (select count(*) from storage.objects where name=r.path and bucket_id=any(r.buckets))<>1
      or not public.media_object_matches_scope(o.bucket_id,o.name,f,v,l,p_target) then
      return jsonb_build_object('code','ATTACHMENT_UNAVAILABLE');
    end if;
    if o.metadata->>'mimetype' not in ('image/jpeg','image/png','image/webp')
      or o.metadata->>'mimetype' is null then
      return jsonb_build_object('code','MEDIA_REVIEW_REQUIRED');
    end if;
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
    refs:=refs || jsonb_build_array(to_jsonb(r));
    objects:=objects || jsonb_build_array(jsonb_build_object(
      'id',o.id,'bucket',o.bucket_id,'path',o.name,'updated_at',o.updated_at,'metadata',o.metadata));
  end loop;
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
    select * into p from content_safety.screening_permissions where user_id=a for share;
    if not found or not p.allowed or p.policy_version<>'openai-safety-text-photo-2026-10-23' then
      return jsonb_build_object('code','PERMISSION_REQUIRED');
    end if;
    permissions:=permissions || jsonb_build_array(jsonb_build_object('user',a,'revision',p.revision::text));
  end loop;
  text_input:=concat_ws(E'\n',m->>'prompt_text',m->>'prompt',m->>'body',
    m->>'people',m->>'location',m->>'memory_date_label',m->>'mood');
  -- UTF-8 bytes are a conservative bound for the adapter's UTF-16 limit.
  if octet_length(text_input)>20000 then return jsonb_build_object('code','TEXT_LIMIT'); end if;
  if btrim(text_input)='' and n=0 then return jsonb_build_object('code','INPUT_EMPTY'); end if;
  source:=jsonb_build_object('target',m,'scope',scope,'refs',refs,'objects',objects,'permissions',permissions);
  return jsonb_build_object('code','READY','revision',encode(sha256(convert_to(source::text,'UTF8')),'hex'),
    'text',text_input,'images',objects);
end;
$$;

create function public.enqueue_content_screening(p_kind text,p_target uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c content_safety.screening_controls; s jsonb; j content_safety.screening_jobs;
begin
  perform content_safety.media_lifecycle_lock();
  select * into c from content_safety.screening_controls where singleton for update;
  s:=content_safety.screening_snapshot(p_kind,p_target,p_actor);
  if s->>'code'<>'READY' then return jsonb_build_object('code',s->>'code'); end if;
  select * into j from content_safety.screening_jobs where target_kind=p_kind and target_id=p_target for update;
  if found and j.revision=s->>'revision' then
    return jsonb_build_object('id',j.id,'state',j.state,'code',j.code);
  end if;
  if (select count(*) from content_safety.screening_jobs where state in ('queued','leased','review')
      and id is distinct from j.id)>=c.max_pending
    or (select count(*) from content_safety.screening_jobs where state in ('queued','leased','review')
      and actor_id=p_actor and id is distinct from j.id)>=c.max_user_pending then
    return jsonb_build_object('code','QUEUE_LIMIT');
  end if;
  insert into content_safety.screening_jobs(target_kind,target_id,actor_id,revision,state,code)
    values(p_kind,p_target,p_actor,s->>'revision','queued','QUEUED')
    on conflict(target_kind,target_id) do update set actor_id=excluded.actor_id,revision=excluded.revision,
      state='queued',code='QUEUED',attempts=0,lease_token=null,lease_until=null,dispatched=false,
      available_at=clock_timestamp(),created_at=clock_timestamp(),updated_at=clock_timestamp()
    returning * into j;
  return jsonb_build_object('id',j.id,'state',j.state,'code',j.code);
end;
$$;

create function public.claim_content_screening()
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
        lease_token=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes',
        dispatched=false,updated_at=clock_timestamp() where id=j.id returning * into j;
      -- No content in claim logs. Load with the exact lease using prepare below.
      return jsonb_build_object('id',j.id,'lease_token',j.lease_token,'revision',j.revision);
    end if;
  end loop;
  return null;
end;
$$;

-- prepare is before downloading/normalizing; authorize is immediately before
-- ONE moderation request and reserves budget once. Neither publishes anything.
create function public.prepare_content_screening(p_job uuid,p_lease uuid,p_authorize boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  c content_safety.screening_controls; j content_safety.screening_jobs; s jsonb;
  day_window bigint:=floor(extract(epoch from clock_timestamp())/86400)::bigint;
  hour_window bigint:=floor(extract(epoch from clock_timestamp())/3600)::bigint;
  global_used integer; user_used integer;
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
  if not p_authorize then return s; end if;
  select used into global_used from content_safety.screening_budgets
    where scope='global_day' and subject='all' and window_start=day_window;
  select used into user_used from content_safety.screening_budgets
    where scope='user_hour' and subject=j.actor_id::text and window_start=hour_window;
  if coalesce(global_used,0)>=c.max_daily_requests or coalesce(user_used,0)>=c.max_user_hourly_requests then
    update content_safety.screening_jobs set state='queued',code='BUDGET_LIMIT',attempts=attempts-1,
      lease_token=null,lease_until=null,available_at=clock_timestamp()+interval '1 hour',
      updated_at=clock_timestamp() where id=j.id;
    return jsonb_build_object('code','BUDGET_LIMIT');
  end if;
  insert into content_safety.screening_budgets values('global_day','all',day_window,1)
    on conflict(scope,subject) do update set window_start=excluded.window_start,
      used=case when screening_budgets.window_start=excluded.window_start then screening_budgets.used+1 else 1 end;
  insert into content_safety.screening_budgets values('user_hour',j.actor_id::text,hour_window,1)
    on conflict(scope,subject) do update set window_start=excluded.window_start,
      used=case when screening_budgets.window_start=excluded.window_start then screening_budgets.used+1 else 1 end;
  update content_safety.screening_jobs set dispatched=true,code='DISPATCH_RESERVED',
    updated_at=clock_timestamp() where id=j.id;
  return jsonb_build_object('code','DISPATCH_RESERVED','revision',j.revision);
end;
$$;

create function public.finish_content_screening(p_job uuid,p_lease uuid,p_outcome text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j content_safety.screening_jobs; s jsonb; next_state text; next_code text;
begin
  if p_outcome is null or p_outcome not in ('clear','review','pending') then
    raise exception 'Invalid screening outcome' using errcode='22023';
  end if;
  perform content_safety.media_lifecycle_lock();
  perform 1 from content_safety.screening_controls where singleton for update;
  select * into j from content_safety.screening_jobs where id=p_job for update;
  if not found or j.state<>'leased' or j.lease_token is distinct from p_lease
    or j.lease_until<=clock_timestamp() or not j.dispatched then
    return jsonb_build_object('code','LEASE_UNAVAILABLE');
  end if;
  s:=content_safety.screening_snapshot(j.target_kind,j.target_id,j.actor_id);
  if s->>'code'<>'READY' or s->>'revision' is distinct from j.revision then
    next_state:='stale'; next_code:='SOURCE_CHANGED';
  elsif p_outcome='pending' then
    next_state:=case when j.attempts<3 then 'queued' else 'review' end;
    next_code:=case when j.attempts<3 then 'PROVIDER_UNAVAILABLE' else 'RETRY_LIMIT' end;
  else
    next_state:=p_outcome;
    next_code:=case when p_outcome='clear' then 'REVISION_CLEAR' else 'HUMAN_REVIEW_REQUIRED' end;
  end if;
  update content_safety.screening_jobs set state=next_state,code=next_code,
    lease_token=null,lease_until=null,dispatched=false,
    available_at=clock_timestamp()+case when j.attempts=1 then interval '1 minute' else interval '5 minutes' end,
    updated_at=clock_timestamp() where id=j.id;
  return jsonb_build_object('state',next_state,'code',next_code);
end;
$$;

-- Worker-only predicate for future publication integration. This is NOT an
-- end-user read grant: RLS, restrictions, family membership and media gates must
-- still be enforced at every read path before the product can be enabled.
create function public.content_screening_revision_clear(p_kind text,p_target uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare j content_safety.screening_jobs; s jsonb;
begin
  perform content_safety.media_lifecycle_lock();
  select * into j from content_safety.screening_jobs where target_kind=p_kind and target_id=p_target;
  if not found or j.state<>'clear' then return false; end if;
  s:=content_safety.screening_snapshot(j.target_kind,j.target_id,j.actor_id);
  return coalesce(s->>'code'='READY' and s->>'revision'=j.revision,false);
end;
$$;

revoke all on function content_safety.screening_snapshot(text,uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.enqueue_content_screening(text,uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.claim_content_screening() from public,anon,authenticated,service_role;
revoke all on function public.prepare_content_screening(uuid,uuid,boolean) from public,anon,authenticated,service_role;
revoke all on function public.finish_content_screening(uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.content_screening_revision_clear(text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.enqueue_content_screening(text,uuid,uuid),public.claim_content_screening(),
  public.prepare_content_screening(uuid,uuid,boolean),public.finish_content_screening(uuid,uuid,text),
  public.content_screening_revision_clear(text,uuid) to service_role;
