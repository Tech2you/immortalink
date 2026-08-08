-- Put hard caps on Supabase Storage uploads so client-side checks are not the
-- only cost-control boundary.
update storage.buckets
set
  file_size_limit = 5 * 1024 * 1024,
  allowed_mime_types = array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif'
  ]::text[]
where id in ('avatars', 'legacy_avatars');

update storage.buckets
set
  file_size_limit = 12 * 1024 * 1024,
  allowed_mime_types = array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif'
  ]::text[]
where id in (
  'memory_photos',
  'vault_photos',
  'legacy_memory_photos',
  'legacy_vault_photos'
);

update storage.buckets
set
  file_size_limit = 25 * 1024 * 1024,
  allowed_mime_types = array[
    'audio/aac',
    'audio/mp4',
    'audio/m4a',
    'audio/mpeg',
    'audio/ogg',
    'audio/wav',
    'audio/webm',
    'audio/x-m4a'
  ]::text[]
where id in (
  'memory_voice',
  'vault_voice',
  'legacy_memory_voice',
  'legacy_vault_voice',
  'voice notes'
);
