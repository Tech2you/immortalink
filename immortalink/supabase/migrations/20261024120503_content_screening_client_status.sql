-- Local candidate only. No switches, existing rows, policies or schedules change.
-- Return a small status vocabulary, never source text, paths, provider responses
-- or another contributor's identity. Permission lookup is not provider dispatch.
create function public.get_content_sharing_status(p_kind text,p_target uuid,p_expected_user_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  u uuid:=auth.uid(); c content_safety.screening_controls;
  o content_safety.screening_origins; j content_safety.screening_jobs;
  scope uuid; f uuid; authors uuid[]; intent boolean; s jsonb; state text;
begin
  if u is null or p_expected_user_id is distinct from u then
    raise exception 'Account changed; reopen sharing' using errcode='42501';
  end if;
  perform content_safety.media_lifecycle_lock();
  if not exists(select 1 from auth.users where id=u)
    or exists(select 1 from public.account_deletion_jobs where user_id=u) then
    return jsonb_build_object('state','unavailable','can_request',false);
  end if;
  if p_kind='memory' then
    select v.id,v.family_id,array[v.owner_id],m.share_to_family_feed
      into scope,f,authors,intent from public.memories m join public.vaults v on v.id=m.vault_id
      where m.id=p_target and v.owner_id=u and content_safety.memory_visible(m.id);
    select * into o from content_safety.screening_origins where memory_id=p_target;
  elsif p_kind='legacy_memory' then
    select l.id,l.family_id,array[m.contributor_id,m.last_editor_id],true
      into scope,f,authors,intent from public.legacy_memories m
      join public.legacy_family_members l on l.id=m.legacy_member_id and l.family_id=m.family_id
      where m.id=p_target and (m.contributor_id=u or m.last_editor_id=u)
        and content_safety.legacy_memory_visible(m.id);
    select * into o from content_safety.screening_origins where legacy_memory_id=p_target;
  end if;
  if scope is null or not exists(select 1 from public.family_members where family_id=f and user_id=u)
    or exists(select 1 from content_safety.restrictions where target_kind='family' and target_id=f) then
    return jsonb_build_object('state','unavailable','can_request',false);
  end if;
  select * into c from content_safety.screening_controls where singleton;
  if c.enforce_publication is not true then
    return jsonb_build_object('state','disabled','can_request',false);
  end if;
  if o.id is null then
    return jsonb_build_object('state','archive','can_request',false);
  end if;
  if o.scope_id is distinct from scope then
    return jsonb_build_object('state','unavailable','can_request',false);
  end if;
  if intent is not true then
    return jsonb_build_object('state','not_requested','can_request',false);
  end if;
  if o.cleared_generation=o.id then
    return jsonb_build_object('state','shared','can_request',false);
  end if;
  if c.enabled is not true then
    return jsonb_build_object('state','paused','can_request',false);
  end if;
  -- Do not ask for text/photo permission on an unsupported voice/video source.
  if exists(select 1 from content_safety.memory_attachment_refs(p_kind,p_target) r
    where r.relation in ('memory_voice_notes','legacy_memory_voice_notes')
      or exists(select 1 from storage.objects b where b.name=r.path and b.bucket_id=any(r.buckets)
        and coalesce(b.metadata->>'mimetype','') not in ('image/jpeg','image/png','image/webp'))) then
    return jsonb_build_object('state','unsupported','can_request',false);
  end if;
  if o.requested_at is null then
    return jsonb_build_object('state','ready','can_request',true);
  end if;
  s:=content_safety.screening_snapshot(p_kind,p_target,u);
  if s->>'code'<>'READY' then
    state:=case s->>'code'
      when 'PERMISSION_REQUIRED' then 'permission_required'
      when 'VOICE_REVIEW_REQUIRED' then 'unsupported'
      when 'MEDIA_REVIEW_REQUIRED' then 'unsupported'
      when 'ATTACHMENT_LIMIT' then 'input_limit'
      when 'ATTACHMENT_SIZE_INVALID' then 'input_limit'
      when 'TEXT_LIMIT' then 'input_limit'
      when 'INPUT_EMPTY' then 'input_limit'
      when 'RESTRICTED_REVIEW_REQUIRED' then 'held'
      else 'unavailable' end;
    return jsonb_build_object('state',state,'can_request',state='permission_required');
  end if;
  select * into j from content_safety.screening_jobs where target_kind=p_kind and target_id=p_target;
  if not found or j.revision is distinct from s->>'revision' then
    return jsonb_build_object('state','ready','can_request',true);
  end if;
  state:=case j.state when 'queued' then 'queued' when 'leased' then 'checking'
    when 'review' then 'held' else 'unavailable' end;
  -- Repeat requests never reset a flag, retry budget or in-flight lease.
  return jsonb_build_object('state',state,'can_request',false);
end;
$$;
revoke all on function public.get_content_sharing_status(text,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_content_sharing_status(text,uuid,uuid) to authenticated;

-- Called only by the existing authenticated Edge notification handler after
-- getUser(). App users cannot forge an actor, audience or publication result.
create function public.memory_notification_audience(p_memory uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v uuid; f uuid; o content_safety.screening_origins; recipients jsonb;
begin
  perform content_safety.media_lifecycle_lock();
  select vv.id,vv.family_id into v,f from public.memories m
    join public.vaults vv on vv.id=m.vault_id
    join auth.users u on u.id=vv.owner_id
    where m.id=p_memory and vv.owner_id=p_actor and m.share_to_family_feed is true;
  if v is null or f is null or not exists(select 1 from public.family_members where family_id=f and user_id=p_actor)
    or exists(select 1 from public.account_deletion_jobs where user_id=p_actor)
    or exists(select 1 from content_safety.restrictions r where
      (r.target_kind='member' and r.target_id=p_actor) or (r.target_kind='memory' and r.target_id=p_memory)
      or (r.target_kind='vault' and r.target_id=v) or (r.target_kind='family' and r.target_id=f)) then
    return jsonb_build_object('allowed',false);
  end if;
  if exists(select 1 from content_safety.screening_controls where singleton and enforce_publication) then
    select * into o from content_safety.screening_origins where memory_id=p_memory;
    if found and (o.scope_id is distinct from v or o.cleared_generation is distinct from o.id) then
      return jsonb_build_object('allowed',false);
    end if;
  end if;
  select coalesce(jsonb_agg(q.user_id order by q.user_id),'[]') into recipients from (
    select distinct fm.user_id from public.family_members fm join auth.users u on u.id=fm.user_id
    where fm.family_id=f and fm.user_id<>p_actor
      and not exists(select 1 from public.account_deletion_jobs where user_id=fm.user_id)
      and not exists(select 1 from content_safety.restrictions where target_kind='member' and target_id=fm.user_id)
      and not exists(select 1 from public.member_blocks b where
        (b.blocker_id=fm.user_id and b.blocked_id=p_actor) or (b.blocker_id=p_actor and b.blocked_id=fm.user_id))
      and not exists(select 1 from public.family_feed_hidden_vaults h where h.user_id=fm.user_id and h.hidden_vault_id=v)
  ) q;
  return jsonb_build_object('allowed',true,'family_id',f,'recipient_ids',recipients);
end;
$$;
revoke all on function public.memory_notification_audience(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.memory_notification_audience(uuid,uuid) to service_role;
