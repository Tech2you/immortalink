-- The authenticated Edge handler supplies its verified caller, never a client actor.
create schema notification_guard;
revoke all on schema notification_guard from public,anon,authenticated,service_role;
create table notification_guard.claims (
  event_key text primary key,
  family_id uuid not null references public.family_groups(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete cascade,
  claimed_at timestamptz not null
);
create index notification_claims_actor_time on notification_guard.claims(actor_id,claimed_at);
create index notification_claims_family_time on notification_guard.claims(family_id,claimed_at);
alter table notification_guard.claims enable row level security;
revoke all on notification_guard.claims from public,anon,authenticated,service_role;

create function public.claim_family_notification(p_type text,p_target uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare f uuid; v uuid; event_time timestamptz; claim_key text; stamp timestamptz;
  recipients jsonb; route jsonb;
begin
  if p_type not in ('memory_added','family_joined') or p_type is null
    or p_target is null or p_actor is null then
    return jsonb_build_object('allowed',false,'code','DENIED');
  end if;
  perform content_safety.media_lifecycle_lock();
  if not exists(select 1 from auth.users where id=p_actor)
    or exists(select 1 from public.account_deletion_jobs where user_id=p_actor) then
    return jsonb_build_object('allowed',false,'code','DENIED');
  end if;
  if p_type='memory_added' then
    select vv.id,vv.family_id,m.created_at into v,f,event_time from public.memories m
      join public.vaults vv on vv.id=m.vault_id
      where m.id=p_target and vv.owner_id=p_actor and m.share_to_family_feed is true;
  else
    select family_id,joined_at into f,event_time from public.family_members
      where family_id=p_target and user_id=p_actor;
  end if;
  if f is null or not exists(select 1 from public.family_members where family_id=f and user_id=p_actor)
    or event_time is null or event_time<clock_timestamp()-interval '24 hours'
    or event_time>clock_timestamp()+interval '1 minute'
    or exists(select 1 from content_safety.restrictions where
      (target_kind='member' and target_id=p_actor) or (target_kind='family' and target_id=f)
      or (target_kind='vault' and target_id=v)
      or (p_type='memory_added' and target_kind='memory' and target_id=p_target)) then
    return jsonb_build_object('allowed',false,'code','DENIED');
  end if;

  -- Respect the optional screening route if that separately approved system is
  -- ever deployed. Missing screening does not activate it or require its tables.
  if p_type='memory_added' and to_regprocedure('public.memory_notification_route(uuid,uuid)') is not null then
    execute 'select public.memory_notification_route($1,$2)' into route using p_target,p_actor;
    if route->'allowed' is distinct from 'true'::jsonb then
      return jsonb_build_object('allowed',false,'code','DENIED');
    end if;
    if route->>'delivery_mode'='outbox' then
      return jsonb_build_object('allowed',false,'code','OUTBOX');
    elsif route->>'delivery_mode' is distinct from 'direct'
      or route->>'family_id' is distinct from f::text
      or jsonb_typeof(route->'recipient_ids') is distinct from 'array' then
      raise exception 'Invalid notification route';
    end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('push-actor:'||p_actor::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('push-family:'||f::text,0));
  stamp:=clock_timestamp();
  -- A memory has one announcement regardless of edits or client-supplied dates.
  -- A new membership can have one welcome; clients cannot edit joined_at.
  claim_key:=p_type||':'||p_target::text||':'||p_actor::text
    ||case when p_type='family_joined' then ':'||extract(epoch from event_time)::text else '' end;
  if exists(select 1 from notification_guard.claims c where c.event_key=claim_key) then
    return jsonb_build_object('allowed',false,'code','DUPLICATE');
  end if;
  if (select count(*) from notification_guard.claims where actor_id=p_actor and claimed_at>stamp-interval '1 hour')>=20
    or (select count(*) from notification_guard.claims where family_id=f and claimed_at>stamp-interval '1 hour')>=50 then
    return jsonb_build_object('allowed',false,'code','RATE_LIMIT');
  end if;

  select coalesce(jsonb_agg(q.user_id order by q.user_id),'[]') into recipients from (
    select distinct fm.user_id from public.family_members fm join auth.users u on u.id=fm.user_id
    where fm.family_id=f and fm.user_id<>p_actor
      and not exists(select 1 from public.account_deletion_jobs where user_id=fm.user_id)
      and not exists(select 1 from content_safety.restrictions where target_kind='member' and target_id=fm.user_id)
      and not exists(select 1 from public.member_blocks b where
        (b.blocker_id=fm.user_id and b.blocked_id=p_actor) or (b.blocker_id=p_actor and b.blocked_id=fm.user_id))
      and not exists(select 1 from public.family_feed_hidden_vaults h where h.user_id=fm.user_id and h.hidden_vault_id=v)
      and (route is null or (route->'recipient_ids') ? fm.user_id::text)
  ) q;
  insert into notification_guard.claims values(claim_key,f,p_actor,stamp);
  return jsonb_build_object('allowed',true,'family_id',f,'recipient_ids',recipients);
end;
$$;
revoke all on function public.claim_family_notification(text,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.claim_family_notification(text,uuid,uuid) to service_role;
