create or replace function public.rename_family(p_family_id uuid, p_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.family_members
    where family_id = p_family_id and user_id = auth.uid() and role = 'owner'
  ) then
    raise exception 'Only a family owner can rename this family' using errcode = '42501';
  end if;
  if p_name is null or length(btrim(p_name)) not between 1 and 100 then
    raise exception 'Family name must contain 1 to 100 characters' using errcode = '22023';
  end if;
  update public.family_groups set name = btrim(p_name) where id = p_family_id;
  if not found then raise exception 'Family not found'; end if;
end;
$$;
revoke all on function public.rename_family(uuid, text) from public, anon;
grant execute on function public.rename_family(uuid, text) to authenticated;
