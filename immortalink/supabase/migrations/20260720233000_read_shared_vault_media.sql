-- Return the media metadata for a vault in one authorized request.  The
-- function checks family membership first, then reads as the function owner so
-- older row-level policies cannot silently hide legacy media from relatives.
create or replace function public.read_shared_vault_media(p_vault_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, storage, pg_temp
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

        union all

        select o.name as path, coalesce(o.created_at, now()) as created_at
        from storage.objects o
        where o.bucket_id = 'vault_photos'
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
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.read_shared_vault_media(uuid) from public;
grant execute on function public.read_shared_vault_media(uuid) to authenticated;

-- Keep direct table reads correct too.  These policies are deliberately based
-- on vault_id for all four metadata tables, matching the actual row shape.
drop policy if exists "multi-family members can view about photos"
  on public.vault_about_photos;
create policy "multi-family members can view about photos"
  on public.vault_about_photos
  for select to authenticated
  using (public.shares_family_with_vault(vault_id));

drop policy if exists "multi-family members can view core voice"
  on public.vault_core_voice_note;
create policy "multi-family members can view core voice"
  on public.vault_core_voice_note
  for select to authenticated
  using (public.shares_family_with_vault(vault_id));

drop policy if exists "multi-family members can view memory photos"
  on public.memory_photos;
create policy "multi-family members can view memory photos"
  on public.memory_photos
  for select to authenticated
  using (public.shares_family_with_vault(vault_id));

drop policy if exists "multi-family members can view memory voice"
  on public.memory_voice_notes;
create policy "multi-family members can view memory voice"
  on public.memory_voice_notes
  for select to authenticated
  using (public.shares_family_with_vault(vault_id));
