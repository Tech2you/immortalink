-- Switch a user's home family without transiently creating two primary rows.
-- The previous single UPDATE could set the new row to true before clearing the
-- old row, which conflicts with family_members_one_primary_per_user.

create or replace function public.set_primary_family(p_family_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1
      from public.family_members
     where family_id = p_family_id
       and user_id = v_user_id
  ) then
    raise exception 'You are not a member of this family';
  end if;

  perform 1
    from public.family_members
   where user_id = v_user_id
   for update;

  update public.family_members
     set is_primary = false
   where user_id = v_user_id
     and is_primary = true;

  update public.family_members
     set is_primary = true
   where user_id = v_user_id
     and family_id = p_family_id;

  update public.vaults
     set family_id = p_family_id
   where owner_id = v_user_id;

  return p_family_id;
end;
$$;

revoke all on function public.set_primary_family(uuid) from public;
grant execute on function public.set_primary_family(uuid) to authenticated;
