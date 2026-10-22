-- A preference is not a transfer of Apple billing or an immediate role change.
create table public.family_account_successors (
  family_id uuid not null references public.family_groups(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  successor_user_id uuid not null references auth.users(id) on delete cascade,
  primary key (family_id, owner_user_id),
  check (owner_user_id <> successor_user_id)
);
alter table public.family_account_successors enable row level security;
revoke all on public.family_account_successors from public, anon, authenticated;
grant all on public.family_account_successors to service_role;

create function public.get_family_account_successors(p_family_id uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.family_members
    where family_id = p_family_id and user_id = auth.uid() and role = 'owner'
  ) then
    raise exception 'Only a family owner can choose a successor' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'selected_user_id', (select successor_user_id from public.family_account_successors
      where family_id = p_family_id and owner_user_id = auth.uid()),
    'members', coalesce((select jsonb_agg(jsonb_build_object(
      'user_id', fm.user_id, 'name', coalesce(v.label, 'Family member')
    ) order by fm.joined_at, fm.user_id)
    from public.family_members fm
    join auth.users u on u.id = fm.user_id
    left join lateral (
      select coalesce(nullif(btrim(display_name), ''), nullif(btrim(name), '')) as label
      from public.vaults where owner_id = fm.user_id order by created_at, id limit 1
    ) v on true
    where fm.family_id = p_family_id and fm.user_id <> auth.uid()), '[]'::jsonb)
  );
end;
$$;

create function public.set_family_account_successor(p_family_id uuid, p_successor_user_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  perform pg_advisory_xact_lock(hashtext(p_family_id::text));
  if auth.uid() is null or not exists (
    select 1 from public.family_members
    where family_id = p_family_id and user_id = auth.uid() and role = 'owner'
  ) then
    raise exception 'Only a family owner can choose a successor' using errcode = '42501';
  end if;
  if p_successor_user_id is null then
    delete from public.family_account_successors
    where family_id = p_family_id and owner_user_id = auth.uid();
    return;
  end if;
  if p_successor_user_id = auth.uid() or not exists (
    select 1 from public.family_members fm join auth.users u on u.id = fm.user_id
    where fm.family_id = p_family_id and fm.user_id = p_successor_user_id
  ) then
    raise exception 'Choose another current family member' using errcode = '22023';
  end if;
  insert into public.family_account_successors values (p_family_id, auth.uid(), p_successor_user_id)
  on conflict (family_id, owner_user_id) do update
    set successor_user_id = excluded.successor_user_id;
end;
$$;

-- Called only by the deletion worker, in the SAME transaction as membership
-- removal. NULL means no real member remains; it is not permission to erase
-- a family without rechecking membership under this advisory lock.
create function public.handoff_family_for_account_deletion(p_family_id uuid, p_user_id uuid)
returns uuid language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_successor uuid;
  v_is_owner boolean;
begin
  perform pg_advisory_xact_lock(hashtext(p_family_id::text));
  select role = 'owner' into v_is_owner from public.family_members
    where family_id = p_family_id and user_id = p_user_id for update;
  if not found then
    raise exception 'Account is not a family member' using errcode = '22023';
  end if;
  select fm.user_id into v_successor
  from public.family_members fm join auth.users u on u.id = fm.user_id
  left join public.family_account_successors s
    on s.family_id = fm.family_id and s.owner_user_id = p_user_id
  where fm.family_id = p_family_id and fm.user_id <> p_user_id
  order by (v_is_owner and fm.user_id = s.successor_user_id) desc nulls last,
    (fm.role = 'owner') desc, fm.joined_at, fm.user_id
  limit 1 for update of fm;
  if v_successor is not null then
    if v_is_owner or not exists (select 1 from public.family_members
      where family_id = p_family_id and user_id <> p_user_id and role = 'owner') then
      update public.family_members set role = 'owner'
        where family_id = p_family_id and user_id = v_successor;
    end if;
    update public.family_groups set created_by = v_successor
      where id = p_family_id and created_by = p_user_id;
    update public.legacy_family_members set created_by = v_successor
      where family_id = p_family_id and created_by = p_user_id;
  end if;
  return v_successor;
end;
$$;

revoke all on function public.get_family_account_successors(uuid) from public, anon;
revoke all on function public.set_family_account_successor(uuid, uuid) from public, anon;
grant execute on function public.get_family_account_successors(uuid) to authenticated;
grant execute on function public.set_family_account_successor(uuid, uuid) to authenticated;
revoke all on function public.handoff_family_for_account_deletion(uuid, uuid) from public, anon, authenticated;
grant execute on function public.handoff_family_for_account_deletion(uuid, uuid) to service_role;
