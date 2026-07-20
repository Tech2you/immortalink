-- Authorize private media by its registered vault metadata before Storage
-- creates a signed URL. This avoids relying solely on folder parsing, while
-- retaining a safe fallback for legacy objects created before media registries
-- existed.
create or replace function public.can_read_shared_media_object(
  p_bucket_id text,
  p_name text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_vault_id uuid;
  v_path_vault_id text;
begin
  if auth.uid() is null then
    return false;
  end if;

  case p_bucket_id
    when 'vault_photos' then
      select media.vault_id
      into v_vault_id
      from (
        select hp.vault_id
        from public.vault_highlight_photos hp
        where hp.path = p_name

        union all

        select ap.vault_id
        from public.vault_about_photos ap
        where ap.path = p_name
      ) media
      limit 1;

    when 'vault_voice' then
      select cv.vault_id
      into v_vault_id
      from public.vault_core_voice_note cv
      where cv.path = p_name
      limit 1;

    when 'memory_photos' then
      select mp.vault_id
      into v_vault_id
      from public.memory_photos mp
      where mp.path = p_name
      limit 1;

    when 'memory_voice' then
      select mv.vault_id
      into v_vault_id
      from public.memory_voice_notes mv
      where mv.path = p_name
      limit 1;

    else
      return false;
  end case;

  -- Older media can pre-date its metadata table. All supported object paths
  -- use owner_id/vault_id/..., so resolve that vault only when it is a UUID.
  if v_vault_id is null then
    v_path_vault_id := split_part(p_name, '/', 2);
    if v_path_vault_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_vault_id := v_path_vault_id::uuid;
    end if;
  end if;

  return v_vault_id is not null
    and public.shares_family_with_vault(v_vault_id);
end;
$$;

revoke all on function public.can_read_shared_media_object(text, text)
  from public;
grant execute on function public.can_read_shared_media_object(text, text)
  to authenticated;

drop policy if exists "family members can read shared vault media"
  on storage.objects;
create policy "family members can read shared vault media"
  on storage.objects
  for select
  to authenticated
  using (public.can_read_shared_media_object(bucket_id, name));
