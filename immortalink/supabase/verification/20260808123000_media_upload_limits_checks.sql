-- Verification for 20260808123000_media_upload_limits.sql.
-- Run this in Supabase SQL Editor after applying the migration.
-- Expected result for the first query: no rows.

with expected_limits(bucket_id, expected_limit, expected_mimes) as (
  values
    ('avatars', 5 * 1024 * 1024, array[
      'image/heic', 'image/heif', 'image/jpeg', 'image/png', 'image/webp'
    ]::text[]),
    ('legacy_avatars', 5 * 1024 * 1024, array[
      'image/heic', 'image/heif', 'image/jpeg', 'image/png', 'image/webp'
    ]::text[]),
    ('memory_photos', 12 * 1024 * 1024, array[
      'image/heic', 'image/heif', 'image/jpeg', 'image/png', 'image/webp'
    ]::text[]),
    ('vault_photos', 12 * 1024 * 1024, array[
      'image/heic', 'image/heif', 'image/jpeg', 'image/png', 'image/webp'
    ]::text[]),
    ('legacy_memory_photos', 12 * 1024 * 1024, array[
      'image/heic', 'image/heif', 'image/jpeg', 'image/png', 'image/webp'
    ]::text[]),
    ('legacy_vault_photos', 12 * 1024 * 1024, array[
      'image/heic', 'image/heif', 'image/jpeg', 'image/png', 'image/webp'
    ]::text[]),
    ('memory_voice', 25 * 1024 * 1024, array[
      'audio/aac', 'audio/m4a', 'audio/mp4', 'audio/mpeg',
      'audio/ogg', 'audio/wav', 'audio/webm', 'audio/x-m4a'
    ]::text[]),
    ('vault_voice', 25 * 1024 * 1024, array[
      'audio/aac', 'audio/m4a', 'audio/mp4', 'audio/mpeg',
      'audio/ogg', 'audio/wav', 'audio/webm', 'audio/x-m4a'
    ]::text[]),
    ('legacy_memory_voice', 25 * 1024 * 1024, array[
      'audio/aac', 'audio/m4a', 'audio/mp4', 'audio/mpeg',
      'audio/ogg', 'audio/wav', 'audio/webm', 'audio/x-m4a'
    ]::text[]),
    ('legacy_vault_voice', 25 * 1024 * 1024, array[
      'audio/aac', 'audio/m4a', 'audio/mp4', 'audio/mpeg',
      'audio/ogg', 'audio/wav', 'audio/webm', 'audio/x-m4a'
    ]::text[]),
    ('voice notes', 25 * 1024 * 1024, array[
      'audio/aac', 'audio/m4a', 'audio/mp4', 'audio/mpeg',
      'audio/ogg', 'audio/wav', 'audio/webm', 'audio/x-m4a'
    ]::text[])
),
actual as (
  select
    e.bucket_id,
    b.public,
    b.file_size_limit,
    coalesce(b.allowed_mime_types, array[]::text[]) as allowed_mime_types,
    e.expected_limit,
    e.expected_mimes
  from expected_limits e
  left join storage.buckets b on b.id = e.bucket_id
)
select
  bucket_id,
  public,
  file_size_limit,
  expected_limit,
  allowed_mime_types,
  expected_mimes,
  case
    when file_size_limit is null then 'missing bucket or missing file_size_limit'
    when public is distinct from false then 'bucket should be private'
    when file_size_limit is distinct from expected_limit then 'wrong file_size_limit'
    when not allowed_mime_types @> expected_mimes then 'missing expected MIME type'
    when not expected_mimes @> allowed_mime_types then 'unexpected MIME type allowed'
  end as issue
from actual
where file_size_limit is null
  or public is distinct from false
  or file_size_limit is distinct from expected_limit
  or not allowed_mime_types @> expected_mimes
  or not expected_mimes @> allowed_mime_types
order by bucket_id;

-- Inspect deployed Storage object policies. Review manually:
-- - SELECT should only allow authorized readers for private media.
-- - INSERT/UPDATE/DELETE policies should prevent writing into another user's
--   or another family's protected media path.
select
  policyname,
  cmd,
  roles,
  qual,
  with_check
from pg_policies
where schemaname = 'storage'
  and tablename = 'objects'
order by policyname, cmd;
