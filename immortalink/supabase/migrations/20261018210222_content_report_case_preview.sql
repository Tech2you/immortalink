-- Operator-only, case-bound previews. No new client privileges or publication rules.
create table content_safety.preview_access (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.content_reports(id),
  reviewer text not null check (char_length(reviewer) between 1 and 200),
  purpose text not null check (purpose in ('content','media')),
  media_id uuid,
  revision text not null,
  created_at timestamptz not null default now()
);
create index preview_access_report_idx on content_safety.preview_access(report_id,created_at);
alter table content_safety.preview_access enable row level security;
revoke all on content_safety.preview_access from public,anon,authenticated;
grant select,insert on content_safety.preview_access to service_role;

create function content_safety.case_snapshot(p_report_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  r public.content_reports; target jsonb; fields jsonb := '{}'::jsonb;
  media jsonb := '[]'::jsonb; result jsonb; legacy_id uuid; vault_id uuid;
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
    elsif r.target_kind='legacy_profile' then
      select to_jsonb(l) into target from public.legacy_family_members l
        where l.id=r.target_id and l.family_id=r.family_id;
      legacy_id:=r.target_id; avatar:=target->>'avatar_path';
      buckets:=array['avatars','vault_photos','legacy_avatars'];
      fields:=jsonb_build_object('Name',coalesce(target->>'display_name',target->>'name'),'About',target->>'about_me_text');
    elsif r.target_kind='vault' then
      select to_jsonb(v) into target from public.vaults v where v.id=r.target_id and v.family_id=r.family_id;
      vault_id:=r.target_id; avatar:=target->>'avatar_path'; buckets:=array['avatars','vault_photos'];
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
      and public.media_object_matches_scope(o.bucket_id,o.name,r.family_id,vault_id,legacy_id,null);
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

create function public.preview_content_report(p_report_id uuid,p_reviewer text,
  p_media_id uuid default null,p_revision text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare snapshot jsonb; item jsonb;
begin
  if nullif(btrim(p_reviewer),'') is null or char_length(p_reviewer)>200 then
    raise exception 'SAFETY_REVIEW_REQUIRED'; end if;
  snapshot:=content_safety.case_snapshot(p_report_id);
  if p_media_id is not null then
    if p_revision is distinct from snapshot->>'revision' then raise exception 'SAFETY_CASE_CHANGED'; end if;
    select value into item from jsonb_array_elements(snapshot->'media') where value->>'id'=p_media_id::text;
    if item is null then raise exception 'SAFETY_MEDIA_UNAVAILABLE'; end if;
  end if;
  insert into content_safety.preview_access(report_id,reviewer,purpose,media_id,revision)
    values(p_report_id,btrim(p_reviewer),case when p_media_id is null then 'content' else 'media' end,
      p_media_id,snapshot->>'revision');
  return case when p_media_id is null then snapshot else item end;
end;
$$;

create function public.review_content_report_checked(p_report_id uuid,p_action text,p_reviewer text,
  p_notes text,p_revision text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare snapshot jsonb;
begin
  perform 1 from public.content_reports where id=p_report_id for update;
  snapshot:=content_safety.case_snapshot(p_report_id);
  if p_revision is distinct from snapshot->>'revision' then raise exception 'SAFETY_CASE_CHANGED'; end if;
  if not exists(select 1 from content_safety.preview_access where report_id=p_report_id
    and reviewer=btrim(p_reviewer) and revision=p_revision and purpose='content'
    and created_at>now()-interval '30 minutes') then raise exception 'SAFETY_PREVIEW_REQUIRED'; end if;
  perform public.review_content_report(p_report_id,p_action,p_reviewer,p_notes);
  return jsonb_build_object('id',p_report_id,'action',p_action,'status',
    (select status from public.content_reports where id=p_report_id));
end;
$$;

revoke all on function content_safety.case_snapshot(uuid) from public,anon,authenticated,service_role;
revoke all on function public.preview_content_report(uuid,text,uuid,text),
  public.review_content_report_checked(uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.preview_content_report(uuid,text,uuid,text),
  public.review_content_report_checked(uuid,text,text,text,text) to service_role;
