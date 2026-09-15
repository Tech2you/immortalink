-- Keep the trigger unprivileged and independent of restricted quota helpers.
create or replace function public.enforce_visual_media_file_limit()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  mime text := lower(coalesce(new.metadata->>'mimetype', ''));
  bytes numeric := 0;
begin
  if new.bucket_id in ('vault_photos', 'memory_photos', 'legacy_vault_photos', 'legacy_memory_photos') then
    if (new.metadata->>'size') ~ '^[0-9]+$' then
      bytes := (new.metadata->>'size')::numeric;
    end if;
    if bytes > 50 * 1024 * 1024 or
       (mime not in ('video/mp4', 'video/quicktime', 'video/x-m4v') and bytes > 12 * 1024 * 1024) then
      raise exception 'Media file exceeds the upload limit' using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.enforce_visual_media_file_limit() from public, anon, authenticated;
