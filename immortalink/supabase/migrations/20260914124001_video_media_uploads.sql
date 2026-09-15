-- Extend existing private media paths so their RLS and family quota checks apply
-- equally to videos. Profile-photo buckets remain image-only at 5 MB.
update storage.buckets
set file_size_limit = 50 * 1024 * 1024,
    allowed_mime_types = array[
      'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
      'video/mp4', 'video/quicktime', 'video/x-m4v'
    ]::text[]
where id in ('vault_photos', 'memory_photos', 'legacy_vault_photos', 'legacy_memory_photos');

-- Preserve the existing 12 MB photo cap inside the mixed-media buckets.
create or replace function public.enforce_visual_media_file_limit()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  mime text := lower(coalesce(new.metadata->>'mimetype', ''));
  bytes bigint := public.everroot_storage_metadata_size(new.metadata);
begin
  if new.bucket_id in ('vault_photos', 'memory_photos', 'legacy_vault_photos', 'legacy_memory_photos') then
    if bytes > 50 * 1024 * 1024 or
       (mime not in ('video/mp4', 'video/quicktime', 'video/x-m4v') and bytes > 12 * 1024 * 1024) then
      raise exception 'Media file exceeds the upload limit' using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_visual_media_file_limit() from public, anon, authenticated;
drop trigger if exists visual_media_file_limit_before_write on storage.objects;
create trigger visual_media_file_limit_before_write
before insert or update of metadata, bucket_id on storage.objects
for each row execute function public.enforce_visual_media_file_limit();

do $$
begin
  if (select count(*) from storage.buckets where id in
    ('vault_photos', 'memory_photos', 'legacy_vault_photos', 'legacy_memory_photos')
    and public = false and file_size_limit = 50 * 1024 * 1024) <> 4 then
    raise exception 'Expected four private video-enabled media buckets';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'storage.objects'::regclass
      and tgname = 'everroot_storage_object_capacity_before_write' and tgenabled = 'O') then
    raise exception 'Family storage quota trigger must remain enabled';
  end if;
end;
$$;
