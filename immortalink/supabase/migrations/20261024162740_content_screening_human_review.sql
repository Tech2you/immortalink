-- Local candidate only: no switches, schedules, backfill or external requests.
-- Automatic checks are not user reports. Keep their decisions and permissions
-- separate from report Hide/Restore and the existing media-retirement workflow.
create table content_safety.screening_reviews (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references content_safety.screening_jobs(id) on delete set null,
  generation uuid not null unique,
  target_kind text not null check(target_kind in ('memory','legacy_memory')),
  target_id uuid not null,
  scope_id uuid not null,
  family_id uuid not null,
  reason text not null check(reason in ('HUMAN_REVIEW_REQUIRED','RETRY_LIMIT')),
  state text not null default 'open' check(state in ('open','reviewing','held','approved','obsolete')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
create index screening_reviews_queue on content_safety.screening_reviews(state,created_at,id);
create table content_safety.screening_review_events (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references content_safety.screening_reviews(id),
  reviewer text not null check(length(reviewer) between 1 and 200),
  action text not null check(action in ('content','media_access','media','review','hold','approve','obsolete')),
  revision text,
  media_id uuid,
  notes text check(length(notes) between 1 and 2000),
  created_at timestamptz not null default clock_timestamp()
);
create index screening_review_events_case on content_safety.screening_review_events(case_id,reviewer,revision,created_at);
alter table content_safety.screening_reviews enable row level security;
alter table content_safety.screening_review_events enable row level security;
revoke all on content_safety.screening_reviews,content_safety.screening_review_events from public,anon,authenticated,service_role;

create function content_safety.capture_screening_review()
returns trigger language plpgsql security definer set search_path='' as $$
declare o content_safety.screening_origins; f uuid; s jsonb;
begin
  if new.state<>'review' or new.code not in ('HUMAN_REVIEW_REQUIRED','RETRY_LIMIT')
    or not exists(select 1 from content_safety.screening_controls where enforce_publication) then return new; end if;
  perform content_safety.media_lifecycle_lock();
  s:=content_safety.screening_snapshot(new.target_kind,new.target_id,new.actor_id);
  if s->>'code'<>'READY' or s->>'revision' is distinct from new.revision then return new; end if;
  select * into o from content_safety.screening_origins where
    (new.target_kind='memory' and memory_id=new.target_id)
    or (new.target_kind='legacy_memory' and legacy_memory_id=new.target_id);
  if not found or o.cleared_generation=o.id then return new; end if;
  if new.target_kind='memory' then select family_id into f from public.vaults where id=o.scope_id;
  else select family_id into f from public.legacy_family_members where id=o.scope_id; end if;
  if f is not null then
    insert into content_safety.screening_reviews(job_id,generation,target_kind,target_id,scope_id,family_id,reason)
      values(new.id,o.id,new.target_kind,new.target_id,o.scope_id,f,new.code)
      on conflict(generation) do nothing;
  end if;
  return new;
end;
$$;
create trigger screening_review_capture after insert or update on content_safety.screening_jobs
  for each row execute function content_safety.capture_screening_review();

-- Edits cannot resurrect an earlier decision or expose new content via an old case.
create function content_safety.obsolete_screening_review()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='DELETE' or new.id is distinct from old.id then
    with changed as (
      update content_safety.screening_reviews set state='obsolete',updated_at=clock_timestamp()
        where generation=old.id and state in ('open','reviewing','held') returning id
    ) insert into content_safety.screening_review_events(case_id,reviewer,action,notes)
        select id,'System','obsolete','Source generation changed or was deleted.' from changed;
  end if;
  return null;
end;
$$;
create trigger screening_review_obsolete after update of id or delete on content_safety.screening_origins
  for each row execute function content_safety.obsolete_screening_review();

-- No provider permission is granted here. This is the disclosed human review of
-- an already-held generation, not permission to send it to an external service.
create function content_safety.screening_review_snapshot(p_case uuid)
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
    for ref in select * from content_safety.memory_attachment_refs(r.target_kind,r.target_id) order by relation,row_id limit 5 loop
      n:=n+1;
      if n>4 or not ref.scope_valid or ref.relation not in ('memory_photos','legacy_memory_photos') then available:=false; exit; end if;
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
    if octet_length(fields::text)>25000 then available:=false; end if;
  end if;
  if not available then fields:='{}'; media:='[]'; m:=null; end if;
  result:=jsonb_build_object('report',jsonb_build_object('id',r.id,'kind',r.target_kind,'status',r.state,
    'reason',r.reason,'createdAt',r.created_at,'accountActionAvailable',false),
    'available',available,'fields',fields,'media',media,'scopeNote',
    'Only the held version and its direct images. Approval does not remove report restrictions or authorize AI processing.');
  return result||jsonb_build_object('revision',md5(result::text||r.generation::text||r.updated_at::text||coalesce(m::text,'')));
end;
$$;

create function public.screening_review_queue(p_state text default 'active')
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if p_state is null or p_state not in ('active','held','approved','obsolete') then raise exception 'Invalid review filter'; end if;
  if not exists(select 1 from content_safety.screening_controls where enforce_publication) then return '[]'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at,q.id),'[]') from (
    select id,target_kind,reason,state as status,created_at from content_safety.screening_reviews
    where (p_state='active' and state in ('open','reviewing')) or state=p_state
    order by created_at,id limit 100
  ) q);
end;
$$;

create function public.preview_screening_review(p_case uuid,p_reviewer text,p_media_id uuid default null,p_revision text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s jsonb; item jsonb;
begin
  if nullif(btrim(p_reviewer),'') is null or length(p_reviewer)>200 then raise exception 'SAFETY_REVIEW_REQUIRED'; end if;
  perform content_safety.media_lifecycle_lock();
  s:=content_safety.screening_review_snapshot(p_case);
  if p_media_id is not null then
    if p_revision is distinct from s->>'revision' then raise exception 'SAFETY_CASE_CHANGED'; end if;
    select value into item from jsonb_array_elements(s->'media') where value->>'id'=p_media_id::text;
    if item is null then raise exception 'SAFETY_MEDIA_UNAVAILABLE'; end if;
  end if;
  insert into content_safety.screening_review_events(case_id,reviewer,action,revision,media_id)
    values(p_case,btrim(p_reviewer),case when p_media_id is null then 'content' else 'media_access' end,s->>'revision',p_media_id);
  return case when p_media_id is null then s else item end;
end;
$$;

-- The private server acknowledges only after bounded retrieval and its second
-- source check. Merely requesting a path, or a failed download, is not a preview.
create function public.ack_screening_review_media(p_case uuid,p_reviewer text,p_media_id uuid,p_revision text)
returns void language plpgsql security definer set search_path='' as $$
declare s jsonb;
begin
  if nullif(btrim(p_reviewer),'') is null or length(p_reviewer)>200 then raise exception 'SAFETY_REVIEW_REQUIRED'; end if;
  perform content_safety.media_lifecycle_lock();
  s:=content_safety.screening_review_snapshot(p_case);
  if p_revision is distinct from s->>'revision' or not exists(
    select 1 from jsonb_array_elements(s->'media') m where m->>'id'=p_media_id::text) then raise exception 'SAFETY_CASE_CHANGED'; end if;
  if not exists(select 1 from content_safety.screening_review_events where case_id=p_case and reviewer=btrim(p_reviewer)
    and revision=p_revision and media_id=p_media_id and action='media_access'
    and created_at>clock_timestamp()-interval '30 minutes') then raise exception 'SAFETY_PREVIEW_REQUIRED'; end if;
  insert into content_safety.screening_review_events(case_id,reviewer,action,revision,media_id)
    values(p_case,btrim(p_reviewer),'media',p_revision,p_media_id);
end;
$$;

create function public.decide_screening_review(p_case uuid,p_action text,p_reviewer text,p_notes text,p_revision text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r content_safety.screening_reviews; s jsonb; next_state text;
begin
  if p_action is null or p_action not in ('review','hold','approve','obsolete')
    or nullif(btrim(p_reviewer),'') is null or length(p_reviewer)>200
    or nullif(btrim(p_notes),'') is null or length(p_notes)>2000 then raise exception 'SAFETY_REVIEW_REQUIRED'; end if;
  perform content_safety.media_lifecycle_lock();
  if not exists(select 1 from content_safety.screening_controls where enforce_publication) then raise exception 'SCREENING_REVIEW_DISABLED'; end if;
  select * into r from content_safety.screening_reviews where id=p_case for update;
  s:=content_safety.screening_review_snapshot(p_case);
  if p_revision is distinct from s->>'revision' or r.state in ('approved','obsolete') then raise exception 'SAFETY_CASE_CHANGED'; end if;
  if not exists(select 1 from content_safety.screening_review_events where case_id=p_case and reviewer=btrim(p_reviewer)
    and revision=p_revision and action='content' and created_at>clock_timestamp()-interval '30 minutes') then raise exception 'SAFETY_PREVIEW_REQUIRED'; end if;
  if p_action='approve' then
    if (s->>'available')::boolean is not true then raise exception 'SAFETY_CASE_CHANGED'; end if;
    if exists(select 1 from jsonb_array_elements(s->'media') m where not exists(
      select 1 from content_safety.screening_review_events e where e.case_id=p_case and e.reviewer=btrim(p_reviewer)
        and e.revision=p_revision and e.action='media' and e.media_id=(m->>'id')::uuid
        and e.created_at>clock_timestamp()-interval '30 minutes')) then raise exception 'SAFETY_MEDIA_PREVIEW_REQUIRED'; end if;
    update content_safety.screening_origins set cleared_generation=id,cleared_at=clock_timestamp() where id=r.generation;
    if not found then raise exception 'SAFETY_CASE_CHANGED'; end if;
    update content_safety.screening_jobs set state='clear',code='HUMAN_APPROVED',lease_token=null,lease_until=null,
      dispatched=false,updated_at=clock_timestamp() where id=r.job_id and state='review';
  elsif p_action='obsolete' and (s->>'available')::boolean then raise exception 'SAFETY_CASE_CHANGED';
  end if;
  next_state:=case p_action when 'review' then 'reviewing' when 'hold' then 'held' when 'approve' then 'approved' else 'obsolete' end;
  update content_safety.screening_reviews set state=next_state,updated_at=clock_timestamp() where id=p_case;
  insert into content_safety.screening_review_events(case_id,reviewer,action,revision,notes)
    values(p_case,btrim(p_reviewer),p_action,p_revision,btrim(p_notes));
  return jsonb_build_object('id',p_case,'action',p_action,'status',next_state);
end;
$$;

-- Consent epoch changes and refreshes must not reroll a flagged generation.
create or replace function public.enqueue_content_screening(p_kind text,p_target uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c content_safety.screening_controls; s jsonb; j content_safety.screening_jobs; held content_safety.screening_reviews;
begin
  perform content_safety.media_lifecycle_lock();
  select * into c from content_safety.screening_controls where singleton for update;
  s:=content_safety.screening_snapshot(p_kind,p_target,p_actor);
  if s->>'code'<>'READY' then return jsonb_build_object('code',s->>'code'); end if;
  select r.* into held from content_safety.screening_reviews r join content_safety.screening_origins o on o.id=r.generation
    where r.target_kind=p_kind and r.target_id=p_target;
  if found then
    return jsonb_build_object('state',case when held.state='approved' then 'clear' else 'review' end,
      'code',case when held.state='approved' then 'HUMAN_APPROVED' else 'HUMAN_REVIEW_REQUIRED' end);
  end if;
  select * into j from content_safety.screening_jobs where target_kind=p_kind and target_id=p_target for update;
  if found and j.revision=s->>'revision' then return jsonb_build_object('id',j.id,'state',j.state,'code',j.code); end if;
  if (select count(*) from content_safety.screening_jobs where state in ('queued','leased','review') and id is distinct from j.id)>=c.max_pending
    or (select count(*) from content_safety.screening_jobs where state in ('queued','leased','review') and actor_id=p_actor and id is distinct from j.id)>=c.max_user_pending then
    return jsonb_build_object('code','QUEUE_LIMIT'); end if;
  insert into content_safety.screening_jobs(target_kind,target_id,actor_id,revision,state,code)
    values(p_kind,p_target,p_actor,s->>'revision','queued','QUEUED')
    on conflict(target_kind,target_id) do update set actor_id=excluded.actor_id,revision=excluded.revision,state='queued',code='QUEUED',
      attempts=0,lease_token=null,lease_until=null,dispatched=false,available_at=clock_timestamp(),created_at=clock_timestamp(),updated_at=clock_timestamp()
    returning * into j;
  return jsonb_build_object('id',j.id,'state',j.state,'code',j.code);
end;
$$;

revoke all on function content_safety.capture_screening_review(),content_safety.obsolete_screening_review(),
  content_safety.screening_review_snapshot(uuid) from public,anon,authenticated,service_role;
revoke all on function public.screening_review_queue(text),public.preview_screening_review(uuid,text,uuid,text),
  public.decide_screening_review(uuid,text,text,text,text),public.ack_screening_review_media(uuid,text,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.screening_review_queue(text),public.preview_screening_review(uuid,text,uuid,text),
  public.decide_screening_review(uuid,text,text,text,text),public.ack_screening_review_media(uuid,text,uuid,text) to service_role;

-- Keep the existing client contract, but a durable human hold precedes provider
-- permission/queue state. Changing consent must not offer another automatic roll.
create or replace function public.get_content_sharing_status(p_kind text,p_target uuid,p_expected_user_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); c content_safety.screening_controls; o content_safety.screening_origins;
  j content_safety.screening_jobs; scope uuid; f uuid; intent boolean; s jsonb; state text;
begin
  if u is null or p_expected_user_id is distinct from u then raise exception 'Account changed; reopen sharing' using errcode='42501'; end if;
  perform content_safety.media_lifecycle_lock();
  if not exists(select 1 from auth.users where id=u) or exists(select 1 from public.account_deletion_jobs where user_id=u) then
    return jsonb_build_object('state','unavailable','can_request',false); end if;
  if p_kind='memory' then
    select v.id,v.family_id,m.share_to_family_feed into scope,f,intent
      from public.memories m join public.vaults v on v.id=m.vault_id
      where m.id=p_target and v.owner_id=u and content_safety.memory_visible(m.id);
    select * into o from content_safety.screening_origins where memory_id=p_target;
  elsif p_kind='legacy_memory' then
    select l.id,l.family_id,true into scope,f,intent from public.legacy_memories m
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
  if exists(select 1 from content_safety.memory_attachment_refs(p_kind,p_target) r
    where r.relation in ('memory_voice_notes','legacy_memory_voice_notes') or exists(
      select 1 from storage.objects b where b.name=r.path and b.bucket_id=any(r.buckets)
        and coalesce(b.metadata->>'mimetype','') not in ('image/jpeg','image/png','image/webp'))) then
    return jsonb_build_object('state','unsupported','can_request',false); end if;
  if o.requested_at is null then return jsonb_build_object('state','ready','can_request',true); end if;
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
  if not found or j.revision is distinct from s->>'revision' then return jsonb_build_object('state','ready','can_request',true); end if;
  state:=case j.state when 'queued' then 'queued' when 'leased' then 'checking' when 'review' then 'held' else 'unavailable' end;
  return jsonb_build_object('state',state,'can_request',false);
end;
$$;
