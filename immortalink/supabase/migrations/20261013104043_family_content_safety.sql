-- Safety is an additional ceiling, never a replacement for family authorization.
create schema content_safety;
revoke all on schema content_safety from public, anon, authenticated;
grant usage on schema content_safety to authenticated, service_role;

create table public.member_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index member_blocks_reverse_idx on public.member_blocks(blocked_id,blocker_id);
alter table public.member_blocks enable row level security;
revoke all on public.member_blocks from public,anon,authenticated;
grant select on public.member_blocks to authenticated;
grant all on public.member_blocks to service_role;
create policy own_blocks on public.member_blocks for select to authenticated
  using (blocker_id=(select auth.uid()));

create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references auth.users(id) on delete set null,
  family_id uuid references public.family_groups(id) on delete set null,
  target_kind text not null check (target_kind in ('member','vault','legacy_profile','legacy_memory','family')),
  target_id uuid not null,
  subject_user_id uuid references auth.users(id) on delete set null,
  reason text not null check (reason in ('harassment','sexual_content','violence','privacy','spam','other')),
  details text not null default '' check (char_length(details)<=1000),
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create index content_reports_queue_idx on public.content_reports(status,created_at);
create index content_reports_family_idx on public.content_reports(family_id);
create index content_reports_subject_idx on public.content_reports(subject_user_id);
create index content_reports_reporter_idx on public.content_reports(reporter_id,created_at);
create unique index content_reports_open_idx on public.content_reports(reporter_id,target_kind,target_id)
  where status in ('open','reviewing');
alter table public.content_reports enable row level security;
revoke all on public.content_reports from public,anon,authenticated;
grant select on public.content_reports to authenticated;
grant all on public.content_reports to service_role;
create policy own_reports on public.content_reports for select to authenticated
  using (reporter_id=(select auth.uid()));

create table content_safety.restrictions (
  target_kind text not null check (target_kind in ('member','vault','legacy_profile','legacy_memory','family')),
  target_id uuid not null,
  report_id uuid references public.content_reports(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (target_kind,target_id)
);
create table content_safety.review_actions (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.content_reports(id),
  action text not null,
  reviewer text not null,
  notes text not null,
  created_at timestamptz not null default now()
);
alter table content_safety.restrictions enable row level security;
alter table content_safety.review_actions enable row level security;
revoke all on all tables in schema content_safety from public,anon,authenticated;
grant all on all tables in schema content_safety to service_role;

-- Unknown historical text authors remain unknown. New attribution is immutable
-- to clients and SET NULL on deletion, preserving shared legacy contributions.
do $$ declare t text; begin
  foreach t in array array['legacy_memories','legacy_member_photos','legacy_memory_photos',
    'legacy_memory_voice_notes','legacy_vault_about_photos','legacy_vault_core_voice_note'] loop
    execute format('alter table public.%I add column contributor_id uuid references auth.users(id) on delete set null',t);
    execute format('alter table public.%I add column last_editor_id uuid references auth.users(id) on delete set null',t);
    execute format('create index %I on public.%I(contributor_id)',t||'_contributor_idx',t);
    execute format('create index %I on public.%I(last_editor_id)',t||'_editor_idx',t);
  end loop;
end $$;

create function content_safety.visible(p_kind text,p_id uuid,p_author uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null
    and not exists(select 1 from content_safety.restrictions r
      where (r.target_kind=p_kind and r.target_id=p_id)
         or (r.target_kind='member' and r.target_id=p_author))
    and not exists(select 1 from public.member_blocks b
      where (b.blocker_id=auth.uid() and b.blocked_id=p_author)
         or (b.blocked_id=auth.uid() and b.blocker_id=p_author));
$$;
create function content_safety.vault_visible(p_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.vaults v where v.id=p_id
    and content_safety.visible('vault',v.id,v.owner_id));
$$;
create function content_safety.legacy_visible(p_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.legacy_family_members l where l.id=p_id
    and content_safety.visible('legacy_profile',l.id));
$$;
create function content_safety.legacy_memory_visible(p_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.legacy_memories m where m.id=p_id
    and content_safety.legacy_visible(m.legacy_member_id)
    and content_safety.visible('legacy_memory',m.id,m.contributor_id)
    and content_safety.visible('legacy_memory',m.id,m.last_editor_id));
$$;
create function content_safety.publication_allowed()
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and not exists(select 1 from content_safety.restrictions
    where target_kind='member' and target_id=auth.uid());
$$;

create function content_safety.guard_publication()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or coalesce(auth.jwt()->>'role','')='service_role' then return new; end if;
  if not content_safety.publication_allowed() then
    raise exception 'SAFETY_ACCOUNT_RESTRICTED' using errcode='42501';
  end if;
  if to_jsonb(new) ? 'contributor_id' then
    if tg_op='INSERT' then new:=jsonb_populate_record(new,jsonb_build_object('contributor_id',auth.uid()));
    elsif (to_jsonb(new)->>'contributor_id') is distinct from (to_jsonb(old)->>'contributor_id') then
      -- FK SET NULL is the only non-service author change allowed.
      if not (to_jsonb(new)->>'contributor_id' is null and not exists(
        select 1 from auth.users where id=(to_jsonb(old)->>'contributor_id')::uuid)) then
        raise exception 'SAFETY_AUTHOR_IMMUTABLE' using errcode='42501';
      end if;
    end if;
    if tg_op='INSERT' then
      new:=jsonb_populate_record(new,jsonb_build_object('last_editor_id',auth.uid()));
    elsif (to_jsonb(new)->>'last_editor_id') is distinct from (to_jsonb(old)->>'last_editor_id') then
      if not (to_jsonb(new)->>'last_editor_id' is null and not exists(
        select 1 from auth.users where id=(to_jsonb(old)->>'last_editor_id')::uuid)) then
        raise exception 'SAFETY_AUTHOR_IMMUTABLE' using errcode='42501';
      end if;
    elsif (to_jsonb(new)-array['contributor_id','last_editor_id']) is distinct from
      (to_jsonb(old)-array['contributor_id','last_editor_id']) then
      new:=jsonb_populate_record(new,jsonb_build_object('last_editor_id',auth.uid()));
    end if;
  end if;
  return new;
end;
$$;

do $$ declare t text; begin
  foreach t in array array['vaults','memories','memory_photos','memory_voice_notes',
    'vault_highlight_photos','vault_about_photos','vault_core_voice_note','vault_voice_notes','voice_notes','vault_media',
    'legacy_family_members','legacy_memories','legacy_member_photos','legacy_memory_photos',
    'legacy_memory_voice_notes','legacy_vault_about_photos','legacy_vault_core_voice_note','family_groups'] loop
    execute format('create trigger safety_publication_guard before insert or update on public.%I
      for each row execute function content_safety.guard_publication()',t);
  end loop;
  foreach t in array array['memories','memory_photos','memory_voice_notes','vault_highlight_photos',
    'vault_about_photos','vault_core_voice_note','vault_voice_notes','voice_notes','vault_media','memory_chunks'] loop
    execute format('create policy safety_read on public.%I as restrictive for select to authenticated
      using(content_safety.vault_visible(vault_id))',t);
  end loop;
  foreach t in array array['legacy_member_photos','legacy_vault_about_photos','legacy_vault_core_voice_note'] loop
    execute format('create policy safety_read on public.%I as restrictive for select to authenticated
      using(content_safety.legacy_visible(legacy_member_id) and content_safety.visible(''contribution'',id,contributor_id)
        and content_safety.visible(''contribution'',id,last_editor_id))',t);
  end loop;
  foreach t in array array['legacy_memory_photos','legacy_memory_voice_notes'] loop
    execute format('create policy safety_read on public.%I as restrictive for select to authenticated
      using(content_safety.legacy_memory_visible(legacy_memory_id) and content_safety.visible(''contribution'',id,contributor_id)
        and content_safety.visible(''contribution'',id,last_editor_id))',t);
  end loop;
end $$;
create policy safety_read on public.vaults as restrictive for select to authenticated
  using(content_safety.visible('vault',id,owner_id));
create policy safety_read on public.legacy_family_members as restrictive for select to authenticated
  using(content_safety.visible('legacy_profile',id));
create policy safety_read on public.legacy_memories as restrictive for select to authenticated
  using(content_safety.legacy_visible(legacy_member_id) and content_safety.visible('legacy_memory',id,contributor_id)
    and content_safety.visible('legacy_memory',id,last_editor_id));
create policy safety_read on public.legacy_memory_chunks as restrictive for select to authenticated
  using(content_safety.legacy_memory_visible(legacy_memory_id));

-- Existing SECURITY DEFINER media readers must observe the same ceiling.
create or replace function public.can_read_vault_media(v_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select content_safety.vault_visible(v_id) and exists(select 1 from public.vaults v where v.id=v_id
    and (v.owner_id=auth.uid() or exists(select 1 from public.family_members fm
      where fm.family_id=v.family_id and fm.user_id=auth.uid())));
$$;
create or replace function public.shares_family_with_vault(p_vault_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select content_safety.vault_visible(p_vault_id) and exists(select 1 from public.vaults v
    join public.family_members theirs on theirs.user_id=v.owner_id
    join public.family_members mine on mine.family_id=theirs.family_id and mine.user_id=auth.uid()
    where v.id=p_vault_id);
$$;
create or replace function public.can_access_legacy_member(p_legacy_member_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select content_safety.legacy_visible(p_legacy_member_id) and exists(select 1 from public.legacy_family_members l
    join public.family_members fm on fm.family_id=l.family_id and fm.user_id=auth.uid()
    where l.id=p_legacy_member_id);
$$;

create view content_safety.legacy_objects as
  select avatar_path as path,id as profile_id,null::uuid as memory_id,null::uuid as contributor_id,null::uuid as last_editor_id from public.legacy_family_members
  union all select path,legacy_member_id,null,contributor_id,last_editor_id from public.legacy_member_photos
  union all select path,legacy_member_id,legacy_memory_id,contributor_id,last_editor_id from public.legacy_memory_photos
  union all select path,legacy_member_id,legacy_memory_id,contributor_id,last_editor_id from public.legacy_memory_voice_notes
  union all select path,legacy_member_id,null,contributor_id,last_editor_id from public.legacy_vault_about_photos
  union all select path,legacy_member_id,null,contributor_id,last_editor_id from public.legacy_vault_core_voice_note;
revoke all on content_safety.legacy_objects from public,anon,authenticated;
create function content_safety.object_visible(p_bucket text,p_path text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare v uuid;
begin
  if p_bucket='family_avatars' then
    select id into v from public.family_groups where id::text=split_part(p_path,'/',1);
    return v is not null and content_safety.visible('family',v);
  end if;
  if p_bucket not in ('avatars','vault_photos','memory_photos','vault_voice','memory_voice','voice notes',
    'legacy_avatars','legacy_vault_photos','legacy_memory_photos','legacy_memory_voice','legacy_vault_voice') then
    return true;
  end if;
  -- Apply a denial if ANY reference is hidden. Existing scope policies still
  -- decide whether a visible reference actually authorizes this object.
  if exists(select 1 from content_safety.legacy_objects r where r.path=p_path and
    (not content_safety.legacy_visible(r.profile_id)
      or (r.memory_id is not null and not content_safety.legacy_memory_visible(r.memory_id))
      or not content_safety.visible('contribution',r.profile_id,r.contributor_id)
      or not content_safety.visible('contribution',r.profile_id,r.last_editor_id))) then return false; end if;
  select id into v from public.vaults where id::text=split_part(p_path,'/',2);
  if v is not null and not content_safety.vault_visible(v) then return false; end if;
  -- Old uploads have no author column; use the immutable object path identity.
  select id into v from auth.users where id::text=split_part(p_path,'/',1);
  return content_safety.visible('contribution',null,v);
end;
$$;
create policy safety_read on storage.objects as restrictive for select to authenticated
  using(content_safety.object_visible(bucket_id,name));
create policy safety_upload on storage.objects as restrictive for insert to authenticated
  with check(content_safety.publication_allowed());
create policy safety_update on storage.objects as restrictive for update to authenticated
  using(content_safety.publication_allowed()) with check(content_safety.publication_allowed());

create function public.set_member_block(p_member_id uuid,p_blocked boolean)
returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();
begin
  if u is null or p_member_id is null or p_member_id=u or p_blocked is null then
    raise exception 'SAFETY_INVALID_MEMBER' using errcode='42501'; end if;
  if not p_blocked then
    delete from public.member_blocks where blocker_id=u and blocked_id=p_member_id;
    return;
  end if;
  if not exists(select 1 from public.family_members a join public.family_members b on a.family_id=b.family_id
    where a.user_id=u and b.user_id=p_member_id) then
    raise exception 'SAFETY_INVALID_MEMBER' using errcode='42501'; end if;
  insert into public.member_blocks(blocker_id,blocked_id) values(u,p_member_id) on conflict do nothing;
end;
$$;

create function public.list_safety_members()
returns table(member_id uuid,display_name text,family_id uuid,family_name text,blocked boolean)
language sql stable security definer set search_path='' as $$
  select distinct b.user_id,coalesce(nullif(v.display_name,''),nullif(v.name,''),'Family member'),
    g.id,g.name,exists(select 1 from public.member_blocks x where x.blocker_id=auth.uid() and x.blocked_id=b.user_id)
  from public.family_members a join public.family_members b on b.family_id=a.family_id and b.user_id<>a.user_id
  join public.family_groups g on g.id=a.family_id
  left join lateral(select display_name,name from public.vaults where owner_id=b.user_id order by created_at limit 1) v on true
  where a.user_id=auth.uid()
  union
  select x.blocked_id,coalesce(nullif(v.display_name,''),nullif(v.name,''),'Former family member'),null,null,true
  from public.member_blocks x left join lateral(select display_name,name from public.vaults where owner_id=x.blocked_id order by created_at limit 1) v on true
  where x.blocker_id=auth.uid() and not exists(select 1 from public.family_members a
    join public.family_members b on b.family_id=a.family_id where a.user_id=auth.uid() and b.user_id=x.blocked_id);
$$;

create function public.report_family_content(p_kind text,p_target_id uuid,p_reason text,p_details text default '',p_family_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); f uuid; author uuid; result uuid;
begin
  if u is null then raise exception 'SAFETY_SIGN_IN_REQUIRED' using errcode='42501'; end if;
  if p_reason is null or p_reason not in ('harassment','sexual_content','violence','privacy','spam','other')
    or char_length(coalesce(p_details,''))>1000 then raise exception 'SAFETY_INVALID_REPORT' using errcode='22023'; end if;
  case p_kind
    when 'member' then
      select b.family_id,b.user_id into f,author from public.family_members b
      where b.user_id=p_target_id and b.family_id=p_family_id;
    when 'vault' then
      select v.family_id,v.owner_id into f,author from public.vaults v where v.id=p_target_id;
    when 'legacy_profile' then
      select l.family_id into f from public.legacy_family_members l where l.id=p_target_id;
    when 'legacy_memory' then
      select l.family_id,coalesce(m.last_editor_id,m.contributor_id) into f,author from public.legacy_memories m
      join public.legacy_family_members l on l.id=m.legacy_member_id where m.id=p_target_id;
    when 'family' then select id into f from public.family_groups where id=p_target_id;
    else raise exception 'SAFETY_INVALID_REPORT' using errcode='22023';
  end case;
  if f is null or not exists(select 1 from public.family_members where family_id=f and user_id=u) then
    raise exception 'SAFETY_CONTENT_UNAVAILABLE' using errcode='42501'; end if;
  -- Serialize per-reporter limits and duplicate handling, including concurrent requests.
  perform pg_advisory_xact_lock(hashtextextended(u::text,741));
  select id into result from public.content_reports where reporter_id=u and target_kind=p_kind
    and target_id=p_target_id and status in ('open','reviewing');
  if result is not null then return result; end if;
  if (select count(*) from public.content_reports where reporter_id=u and created_at>now()-interval '1 hour')>=10 then
    raise exception 'SAFETY_REPORT_LIMIT' using errcode='P0001'; end if;
  insert into public.content_reports(reporter_id,family_id,target_kind,target_id,subject_user_id,reason,details)
    values(u,f,p_kind,p_target_id,author,p_reason,btrim(coalesce(p_details,''))) returning id into result;
  return result;
end;
$$;

-- Operator-only, audited and reversible. A report never deletes shared media.
create function public.review_content_report(p_report_id uuid,p_action text,p_reviewer text,p_notes text)
returns void language plpgsql security definer set search_path='' as $$
declare r public.content_reports; kind text; target uuid;
begin
  if nullif(btrim(p_reviewer),'') is null or nullif(btrim(p_notes),'') is null
    or char_length(p_notes)>2000 or char_length(p_reviewer)>200 then raise exception 'SAFETY_REVIEW_REQUIRED'; end if;
  select * into r from public.content_reports where id=p_report_id for update;
  if not found then raise exception 'SAFETY_REPORT_NOT_FOUND'; end if;
  if p_action is null or p_action not in ('review','dismiss','hide','restore','suspend','reinstate') then
    raise exception 'SAFETY_INVALID_ACTION'; end if;
  kind:=r.target_kind; target:=r.target_id;
  if p_action in ('suspend','reinstate') then
    -- A shared profile creator is not assumed to be the author of its contents.
    if r.subject_user_id is null then raise exception 'SAFETY_AUTHOR_UNKNOWN'; end if;
    kind:='member'; target:=r.subject_user_id;
  end if;
  if p_action in ('hide','suspend') then
    insert into content_safety.restrictions(target_kind,target_id,report_id) values(kind,target,r.id) on conflict do nothing;
  elsif p_action in ('restore','reinstate') then
    delete from content_safety.restrictions where target_kind=kind and target_id=target;
  end if;
  update public.content_reports set status=case p_action when 'review' then 'reviewing' when 'dismiss' then 'dismissed' else 'resolved' end,
    reviewed_at=now() where id=r.id;
  insert into content_safety.review_actions(report_id,action,reviewer,notes) values(r.id,p_action,btrim(p_reviewer),btrim(p_notes));
end;
$$;

revoke all on all functions in schema content_safety from public,anon,authenticated;
grant execute on function content_safety.visible(text,uuid,uuid),content_safety.vault_visible(uuid),
  content_safety.legacy_visible(uuid),content_safety.legacy_memory_visible(uuid),
  content_safety.publication_allowed(),content_safety.object_visible(text,text) to authenticated;
revoke all on function public.set_member_block(uuid,boolean),public.list_safety_members(),
  public.report_family_content(text,uuid,text,text,uuid),public.review_content_report(uuid,text,text,text)
  from public,anon,authenticated;
grant execute on function public.set_member_block(uuid,boolean),public.list_safety_members(),
  public.report_family_content(text,uuid,text,text,uuid) to authenticated;
grant execute on function public.review_content_report(uuid,text,text,text) to service_role;
