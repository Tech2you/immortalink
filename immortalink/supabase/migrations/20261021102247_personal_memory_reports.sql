-- Exact personal-memory reports; no change to billing, membership or editing.
alter table public.content_reports drop constraint content_reports_target_kind_check;
alter table public.content_reports add constraint content_reports_target_kind_check
  check (target_kind in ('member','vault','memory','legacy_profile','legacy_memory','family'));
alter table content_safety.restrictions drop constraint restrictions_target_kind_check;
alter table content_safety.restrictions add constraint restrictions_target_kind_check
  check (target_kind in ('member','vault','memory','legacy_profile','legacy_memory','family'));

create function content_safety.memory_visible(p_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.memories m join public.vaults v on v.id=m.vault_id
    where m.id=p_id and content_safety.vault_visible(v.id)
      and content_safety.visible('memory',m.id,v.owner_id));
$$;
revoke all on function content_safety.memory_visible(uuid) from public,anon,authenticated;
grant execute on function content_safety.memory_visible(uuid) to authenticated;

-- These remain restrictive ceilings on existing authorization, not new read grants.
create policy safety_memory_read on public.memories as restrictive for select to authenticated
  using(content_safety.memory_visible(id));
create policy safety_memory_read on public.memory_photos as restrictive for select to authenticated
  using(content_safety.memory_visible(memory_id));
create policy safety_memory_read on public.memory_voice_notes as restrictive for select to authenticated
  using(content_safety.memory_visible(memory_id));
create policy safety_memory_read on public.memory_chunks as restrictive for select to authenticated
  using(content_safety.memory_visible(memory_id));

create index if not exists memory_photos_path_idx on public.memory_photos(path);
create index if not exists memory_voice_notes_path_idx on public.memory_voice_notes(path);


create or replace function public.report_family_content(p_kind text,p_target_id uuid,p_reason text,p_details text default '',p_family_id uuid default null)
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
    when 'memory' then
      -- Follow existing vault access, including a shared non-primary family.
      -- The caller cannot select another family as the review scope.
      select mine.family_id,v.owner_id into f,author
      from public.memories m join public.vaults v on v.id=m.vault_id
      join public.family_members mine on mine.user_id=u
        and (mine.family_id=v.family_id or exists(
          select 1 from public.family_members theirs
          where theirs.family_id=mine.family_id and theirs.user_id=v.owner_id))
      where m.id=p_target_id and content_safety.memory_visible(m.id)
        and (p_family_id is null or mine.family_id=p_family_id)
      order by (mine.family_id=v.family_id) desc,mine.family_id limit 1;
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

create or replace function content_safety.object_visible(p_bucket text,p_path text)
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
  if exists(select 1 from public.memory_photos p where p.path=p_path
    and p_bucket in ('vault_photos','memory_photos')
    and not content_safety.memory_visible(p.memory_id)) then return false; end if;
  if exists(select 1 from public.memory_voice_notes n where n.path=p_path
    and p_bucket='memory_voice'
    and not content_safety.memory_visible(n.memory_id)) then return false; end if;
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

-- Return the media metadata for a vault in one authorized request.  The
-- function checks family membership first, then reads as the function owner so
-- older row-level policies cannot silently hide legacy media from relatives.
create or replace function public.read_shared_vault_media(p_vault_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not public.shares_family_with_vault(p_vault_id) then
    raise exception 'You do not have access to this vault.'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'highlights', coalesce((
      select jsonb_agg(to_jsonb(h) order by h.created_at)
      from (
        select hp.path, hp.created_at
        from public.vault_highlight_photos hp
        where hp.vault_id = p_vault_id
          and content_safety.object_visible('vault_photos',hp.path)

        union all

        select o.name as path, coalesce(o.created_at, now()) as created_at
        from storage.objects o
        where o.bucket_id = 'vault_photos'
          and content_safety.object_visible(o.bucket_id,o.name)
          and (storage.foldername(o.name))[2] = p_vault_id::text
          and (storage.foldername(o.name))[3] = 'featured'
          and not exists (
            select 1
            from public.vault_highlight_photos registered
            where registered.path = o.name
          )
      ) h
    ), '[]'::jsonb),
    'about_photos', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', ap.id,
          'path', ap.path,
          'created_at', ap.created_at
        )
        order by ap.created_at desc
      )
      from public.vault_about_photos ap
      where ap.vault_id = p_vault_id
        and content_safety.object_visible('vault_photos',ap.path)
    ), '[]'::jsonb),
    'core_voice', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', cv.id,
          'path', cv.path,
          'title', cv.title,
          'created_at', cv.created_at
        )
        order by cv.created_at desc
      )
      from public.vault_core_voice_note cv
      where cv.vault_id = p_vault_id
        and content_safety.object_visible('vault_voice',cv.path)
    ), '[]'::jsonb),
    'memory_photos', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', mp.id,
          'memory_id', mp.memory_id,
          'path', mp.path,
          'created_at', mp.created_at
        )
        order by mp.created_at desc
      )
      from public.memory_photos mp
      where mp.vault_id = p_vault_id
        and content_safety.memory_visible(mp.memory_id)
    ), '[]'::jsonb),
    'memory_voice', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', mv.id,
          'memory_id', mv.memory_id,
          'path', mv.path,
          'title', mv.title,
          'created_at', mv.created_at
        )
        order by mv.created_at desc
      )
      from public.memory_voice_notes mv
      where mv.vault_id = p_vault_id
        and content_safety.memory_visible(mv.memory_id)
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.read_shared_vault_media(uuid) from public;
grant execute on function public.read_shared_vault_media(uuid) to authenticated;



create or replace function content_safety.case_snapshot(p_report_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  r public.content_reports; target jsonb; fields jsonb := '{}'::jsonb;
  media jsonb := '[]'::jsonb; result jsonb; legacy_id uuid; target_vault_id uuid;
  avatar text; buckets text[]; scope_note text;
begin
  select * into r from public.content_reports where id=p_report_id;
  if not found then raise exception 'SAFETY_REPORT_NOT_FOUND'; end if;
  -- An old report must not become a way into a target's new family.
  if r.family_id is not null then
    if r.target_kind='legacy_memory' then
      select to_jsonb(m),m.legacy_member_id into target,legacy_id
      from public.legacy_memories m join public.legacy_family_members l on l.id=m.legacy_member_id
      where m.id=r.target_id and m.family_id=r.family_id and l.family_id=r.family_id;
      fields := jsonb_build_object('Prompt',target->>'prompt_text','Memory',target->>'body');
      scope_note := 'Current reported memory and its direct attachments only. This is not a preserved copy from the time of reporting.';
      if target is not null then
        select coalesce(jsonb_agg(item order by item->>'id'),'[]'::jsonb) into media from (
          select jsonb_build_object('id',o.id,'kind',a.kind,'bucket',o.bucket_id,'path',o.name,
            'stamp',o.updated_at,'metadata',o.metadata) item
          from (
            select p.path,'image'::text kind,array['vault_photos','memory_photos','legacy_memory_photos'] allowed
            from public.legacy_memory_photos p where p.legacy_memory_id=r.target_id
              and p.legacy_member_id=legacy_id and p.family_id=r.family_id
            union all
            select v.path,'audio',array['memory_voice','legacy_memory_voice']
            from public.legacy_memory_voice_notes v where v.legacy_memory_id=r.target_id
              and v.legacy_member_id=legacy_id and v.family_id=r.family_id
          ) a join storage.objects o on o.name=a.path and o.bucket_id=any(a.allowed)
          where public.media_object_matches_scope(o.bucket_id,o.name,r.family_id,null,legacy_id,r.target_id)
          order by o.id limit 51
        ) limited;
      end if;
    elsif r.target_kind='memory' then
      select to_jsonb(m),m.vault_id into target,target_vault_id
      from public.memories m join public.vaults v on v.id=m.vault_id
      where m.id=r.target_id and v.owner_id=r.subject_user_id
        and (v.family_id=r.family_id or exists(select 1 from public.family_members f
          where f.family_id=r.family_id and f.user_id=v.owner_id));
      fields:=jsonb_build_object('Prompt',coalesce(target->>'prompt_text',target->>'prompt'),
        'Memory',target->>'body','Date',target->>'memory_date_label',
        'People',target->>'people','Location',target->>'location','Mood',target->>'mood');
      scope_note:='Current reported memory and its direct attachments only. This is not a preserved copy from the time of reporting.';
      if target is not null then
        select coalesce(jsonb_agg(item order by item->>'id'),'[]'::jsonb) into media from (
          select jsonb_build_object('id',o.id,'kind',a.kind,'bucket',o.bucket_id,'path',o.name,
            'stamp',o.updated_at,'metadata',o.metadata) item
          from (
            select p.path,'image'::text kind,array['vault_photos','memory_photos'] allowed
            from public.memory_photos p where p.memory_id=r.target_id and p.vault_id=target_vault_id
            union all
            select n.path,'audio',array['memory_voice']
            from public.memory_voice_notes n where n.memory_id=r.target_id and n.vault_id=target_vault_id
          ) a join storage.objects o on o.name=a.path and o.bucket_id=any(a.allowed)
          where public.media_object_matches_scope(o.bucket_id,o.name,r.family_id,target_vault_id,null,r.target_id)
          order by o.id limit 51
        ) limited;
      end if;
    elsif r.target_kind='legacy_profile' then
      select to_jsonb(l) into target from public.legacy_family_members l
        where l.id=r.target_id and l.family_id=r.family_id;
      legacy_id:=r.target_id; avatar:=target->>'avatar_path';
      buckets:=array['avatars','vault_photos','legacy_avatars'];
      fields:=jsonb_build_object('Name',coalesce(target->>'display_name',target->>'name'),'About',target->>'about_me_text');
    elsif r.target_kind='vault' then
      select to_jsonb(v) into target from public.vaults v where v.id=r.target_id and v.family_id=r.family_id;
      target_vault_id:=r.target_id; avatar:=target->>'avatar_path'; buckets:=array['avatars','vault_photos'];
      fields:=jsonb_build_object('Name',coalesce(target->>'display_name',target->>'name'));
    elsif r.target_kind='member' then
      -- Display identity only. Never expand a member report into their vaults.
      select jsonb_build_object('Name',coalesce(v.display_name,v.name)) into target
        from public.vaults v where v.owner_id=r.target_id and v.family_id=r.family_id
        and exists(select 1 from public.family_members f where f.family_id=r.family_id and f.user_id=r.target_id)
        order by v.id limit 1;
      fields:=coalesce(target,'{}'::jsonb);
    elsif r.target_kind='family' then
      select jsonb_build_object('Name',f.name) into target from public.family_groups f
        where f.id=r.target_id and f.id=r.family_id;
      fields:=coalesce(target,'{}'::jsonb);
    end if;
  end if;
  if avatar is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'kind','image','bucket',o.bucket_id,
      'path',o.name,'stamp',o.updated_at,'metadata',o.metadata) order by o.id),'[]'::jsonb)
      into media from storage.objects o where o.name=avatar and o.bucket_id=any(buckets)
      and public.media_object_matches_scope(o.bucket_id,o.name,r.family_id,target_vault_id,legacy_id,null);
  end if;
  if jsonb_array_length(media)>50 then raise exception 'SAFETY_CASE_TOO_LARGE'; end if;
  if octet_length(fields::text)>200000 then raise exception 'SAFETY_CASE_TOO_LARGE'; end if;
  result:=jsonb_build_object('report',jsonb_build_object('id',r.id,'kind',r.target_kind,
    'reason',r.reason,'details',r.details,'status',r.status,'createdAt',r.created_at,
    'reviewedAt',r.reviewed_at,'accountActionAvailable',r.subject_user_id is not null),
    'available',target is not null,'fields',jsonb_strip_nulls(fields),'media',media,
    'scopeNote',coalesce(scope_note,'Profile-level report: limited identity/profile context only. No gallery, other memories or family archive access. Obtain an item-specific report before reviewing other content.'));
  -- Fingerprint is a freshness check, never an authorization credential.
  return result || jsonb_build_object('revision',md5(result::text || coalesce(target::text,'')));
end;
$$;

revoke all on function content_safety.case_snapshot(uuid) from public,anon,authenticated,service_role;
revoke all on function public.report_family_content(text,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.report_family_content(text,uuid,text,text,uuid) to authenticated;

