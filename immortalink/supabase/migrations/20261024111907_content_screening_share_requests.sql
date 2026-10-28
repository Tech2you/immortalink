-- Staged only. No backfill, network dispatch, read-policy or upload changes.
-- A database-observed insertion, not a client-editable date, defines new content.
create table content_safety.screening_origins (
  id uuid primary key default gen_random_uuid(),
  memory_id uuid unique references public.memories(id) on delete cascade,
  legacy_memory_id uuid unique references public.legacy_memories(id) on delete cascade,
  scope_id uuid not null,
  recorded_at timestamptz not null default clock_timestamp(),
  requested_at timestamptz,
  check (num_nonnulls(memory_id,legacy_memory_id)=1)
);
alter table content_safety.screening_origins enable row level security;
revoke all on content_safety.screening_origins from public,anon,authenticated,service_role;

create function content_safety.track_screening_origin()
returns trigger language plpgsql security definer set search_path='' as $$
declare c content_safety.screening_controls; kind text;
begin
  perform content_safety.media_lifecycle_lock();
  kind:=case when tg_table_name='memories' then 'memory' else 'legacy_memory' end;
  if tg_op='DELETE' then
    -- Tickets cascade from jobs; the origin cascades from its actual source row.
    delete from content_safety.screening_jobs where target_kind=kind and target_id=old.id;
    return old;
  end if;
  select * into c from content_safety.screening_controls where singleton for share;
  -- Once capture has started, pausing processing must not turn new inserts into
  -- exempt archives. Initial installation has no cutoff and captures nothing.
  if c.eligible_after is null or clock_timestamp()<c.eligible_after then
    return new;
  end if;
  if kind='memory' then
    insert into content_safety.screening_origins(memory_id,scope_id) values(new.id,new.vault_id);
  else
    insert into content_safety.screening_origins(legacy_memory_id,scope_id) values(new.id,new.legacy_member_id);
  end if;
  return new;
end;
$$;
revoke all on function content_safety.track_screening_origin() from public,anon,authenticated,service_role;
create trigger screening_origin after insert or delete on public.memories
  for each row execute function content_safety.track_screening_origin();
create trigger screening_origin after insert or delete on public.legacy_memories
  for each row execute function content_safety.track_screening_origin();

-- Replace the staged snapshot in place, retaining its OID for existing callers.
-- Every queue/claim/prepare/finish check now requires the trusted origin/request.
create or replace function content_safety.screening_snapshot(p_kind text,p_target uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  c content_safety.screening_controls; origin content_safety.screening_origins;
  m jsonb; scope jsonb; actors uuid[]; permissions jsonb := '[]';
  refs jsonb := '[]'; objects jsonb := '[]'; text_input text;
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
  if octet_length(text_input)>20000 then return jsonb_build_object('code','TEXT_LIMIT'); end if;
  if btrim(text_input)='' and n=0 then return jsonb_build_object('code','INPUT_EMPTY'); end if;
  source:=jsonb_build_object('target',m,'scope',scope,'refs',refs,'objects',objects,
    'permissions',permissions,'origin',origin.id);
  return jsonb_build_object('code','READY','revision',encode(sha256(convert_to(source::text,'UTF8')),'hex'),
    'text',text_input,'images',objects);
end;
$$;
revoke all on function content_safety.screening_snapshot(text,uuid,uuid) from public,anon,authenticated,service_role;

-- Caller-bound entry point; does not grant consent, upload or publish content.
create function public.request_content_screening(p_kind text,p_target uuid,p_expected_user_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); c content_safety.screening_controls; origin_id uuid;
begin
  if u is null or p_expected_user_id is distinct from u then
    raise exception 'Account changed; reopen sharing' using errcode='42501';
  end if;
  perform content_safety.media_lifecycle_lock();
  select * into c from content_safety.screening_controls where singleton for update;
  if c.enabled is not true or c.eligible_after is null then
    return jsonb_build_object('code','SCREENING_DISABLED');
  end if;
  if not exists(select 1 from auth.users where id=u)
    or exists(select 1 from public.account_deletion_jobs where user_id=u) then
    return jsonb_build_object('code','REQUEST_UNAVAILABLE');
  end if;
  if p_kind='memory' then
    select o.id into origin_id from content_safety.screening_origins o
      join public.memories m on m.id=o.memory_id
      join public.vaults v on v.id=m.vault_id and v.id=o.scope_id
      where m.id=p_target and v.owner_id=u and m.share_to_family_feed is true
        and exists(select 1 from public.family_members where family_id=v.family_id and user_id=u);
  elsif p_kind='legacy_memory' then
    select o.id into origin_id from content_safety.screening_origins o
      join public.legacy_memories m on m.id=o.legacy_memory_id
      join public.legacy_family_members l on l.id=m.legacy_member_id and l.id=o.scope_id and l.family_id=m.family_id
      where m.id=p_target and (m.contributor_id=u or m.last_editor_id=u)
        and exists(select 1 from public.family_members where family_id=l.family_id and user_id=u);
  end if;
  -- Same response for absent, archived and unauthorized targets; no content leaks.
  if origin_id is null then return jsonb_build_object('code','REQUEST_UNAVAILABLE'); end if;
  update content_safety.screening_origins set requested_at=coalesce(requested_at,clock_timestamp()) where id=origin_id;
  return public.enqueue_content_screening(p_kind,p_target,u);
end;
$$;
revoke all on function public.request_content_screening(text,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.request_content_screening(text,uuid,uuid) to authenticated;
