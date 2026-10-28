-- Uncapped real-member totals, bounded legacy profiles and rolling invite rates.
-- No existing membership, content, entitlement or Storage object is rewritten.
create schema if not exists family_access;
revoke all on schema family_access from public, anon, authenticated;

-- Admission imports the member's existing media into family usage. Use the
-- existing media lifecycle lock before join RPCs acquire invite/vault row locks,
-- matching uploads and membership statement triggers to avoid lock inversion.
do $$
declare target regprocedure; definition text;
begin
  if to_regprocedure('content_safety.media_lifecycle_lock()') is null then
    raise exception 'Media lifecycle locking must be present before changing admission';
  end if;
  foreach target in array array[
    'public.join_family_by_invite(text)'::regprocedure,
    'public.join_family_by_relationship_invite(text)'::regprocedure
  ] loop
    definition := pg_get_functiondef(target);
    if position(E'\nbegin\n' in definition)=0 then
      raise exception 'Unexpected join RPC definition; inspect before applying';
    end if;
    definition := replace(definition,E'\nbegin\n',
      E'\nbegin\n  perform content_safety.media_lifecycle_lock();\n');
    execute definition;
  end loop;
end;
$$;

-- Accepted relationship invites are deleted. Rate accounting must survive
-- that deletion and must not trust client-supplied timestamps or edited codes.
create table family_access.invite_rate_events (
  invite_id uuid primary key,
  family_id uuid not null references public.family_groups(id) on delete cascade,
  actor_id uuid not null,
  created_at timestamptz not null default clock_timestamp()
);
create index invite_rate_events_family_time on family_access.invite_rate_events(family_id, created_at);
create index invite_rate_events_actor_time on family_access.invite_rate_events(actor_id, created_at);
alter table family_access.invite_rate_events enable row level security;
revoke all on family_access.invite_rate_events from public, anon, authenticated;

insert into family_access.invite_rate_events(invite_id,family_id,actor_id,created_at)
select id,family_id,created_by,least(created_at,clock_timestamp())
from public.family_invites where created_at>clock_timestamp()-interval '1 hour'
  and created_by is not null;

create function family_access.assert_growth_storage(p_family_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_family_id is null then return; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_family_id::text || ':storage'));
  if public.everroot_storage_bytes_used(p_family_id,null)
      >= public.everroot_limit_bigint(p_family_id,'storage_bytes') then
    perform public.everroot_quota_error('ERR_EVERROOT_STORAGE_LIMIT',
      'This family storage is full. Free up space or change the family plan before adding another person. Existing members keep their access.');
  end if;
end;
$$;
revoke all on function family_access.assert_growth_storage(uuid) from public, anon, authenticated, service_role;

create or replace function public.everroot_assert_can_add_family_member(p_family_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare incoming_bytes bigint := 0; used_bytes bigint; limit_bytes bigint;
begin
  if p_family_id is null or p_user_id is null then return; end if;
  perform content_safety.media_lifecycle_lock();
  -- Same-family upserts are not new admissions and must work even when full.
  if exists(select 1 from public.family_members where family_id=p_family_id and user_id=p_user_id) then return; end if;
  perform public.everroot_assert_family_writable(p_family_id);
  perform family_access.assert_growth_storage(p_family_id);
  used_bytes := public.everroot_storage_bytes_used(p_family_id,null);
  limit_bytes := public.everroot_limit_bigint(p_family_id,'storage_bytes');
  select coalesce(sum(public.everroot_storage_bytes_used(null,v.id)),0)
    into incoming_bytes from public.vaults v where v.owner_id=p_user_id;
  if used_bytes+incoming_bytes>limit_bytes then
    perform public.everroot_quota_error('ERR_EVERROOT_STORAGE_LIMIT',
      'This family does not have enough storage for this member''s existing media. Free up space or change the family plan first.');
  end if;
end;
$$;

create or replace function public.everroot_assert_family_member_capacity()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op='UPDATE' and new.family_id is not distinct from old.family_id
      and new.user_id is not distinct from old.user_id then return new; end if;
  perform public.everroot_assert_can_add_family_member(new.family_id,new.user_id);
  return new;
end;
$$;
drop trigger everroot_family_member_capacity_before_insert on public.family_members;
create trigger everroot_family_member_capacity_before_insert
before insert or update of family_id,user_id on public.family_members
for each row execute function public.everroot_assert_family_member_capacity();

-- Retain expired-plan read-only behavior, but member count is no longer a
-- reason for a family to become read-only. All other checks remain unchanged.
create or replace function public.everroot_family_is_read_only(p_family_id uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare v_limits jsonb;
begin
  if p_family_id is null or public.everroot_family_plan(p_family_id)<>'free' then return false; end if;
  v_limits := public.everroot_limits(p_family_id);
  return public.everroot_storage_bytes_used(p_family_id,null)>(v_limits->>'storage_bytes')::bigint
    or public.everroot_memory_count(p_family_id,null)>(v_limits->>'memories')::integer
    or public.everroot_photo_count(p_family_id,null)>(v_limits->>'photos')::integer
    or public.everroot_voice_note_count(p_family_id,null)>(v_limits->>'voice_notes')::integer
    or (select count(*) from public.legacy_family_members
      where family_id=p_family_id and replaced_by_vault_id is null)>(v_limits->>'legacy_people')::integer;
end;
$$;

create or replace function public.everroot_assert_legacy_person_capacity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare cap integer; used integer;
begin
  if tg_op='UPDATE' and new.family_id is not distinct from old.family_id
      and not (old.replaced_by_vault_id is not null and new.replaced_by_vault_id is null) then return new; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(new.family_id::text || ':legacy_people'));
  perform public.everroot_assert_family_writable(new.family_id);
  perform family_access.assert_growth_storage(new.family_id);
  cap := public.everroot_limit_int(new.family_id,'legacy_people');
  -- Count retained/replaced profiles too: flagging a profile as replaced must
  -- not allow unlimited rows to be manufactured outside the profile allowance.
  select count(*) into used from public.legacy_family_members
    where family_id=new.family_id and (tg_op='INSERT' or id<>old.id);
  if used>=cap then
    perform public.everroot_quota_error('ERR_EVERROOT_LEGACY_LIMIT',
      'This family has reached its limit of ' || cap || ' legacy profiles. Remove an unused profile or change the family plan.');
  end if;
  return new;
end;
$$;
drop trigger everroot_legacy_person_capacity_before_insert on public.legacy_family_members;
create trigger everroot_legacy_person_capacity_before_insert
before insert or update of family_id,replaced_by_vault_id on public.legacy_family_members
for each row execute function public.everroot_assert_legacy_person_capacity();


revoke all on function public.everroot_assert_can_add_family_member(uuid,uuid),
  public.everroot_assert_family_member_capacity(),public.everroot_assert_legacy_person_capacity(),
  public.everroot_assert_invite_capacity(),public.everroot_family_is_read_only(uuid)
  from public,anon,authenticated;
grant execute on function public.everroot_assert_can_add_family_member(uuid,uuid),
  public.everroot_assert_family_member_capacity(),public.everroot_assert_legacy_person_capacity(),
  public.everroot_assert_invite_capacity(),public.everroot_family_is_read_only(uuid) to service_role;
