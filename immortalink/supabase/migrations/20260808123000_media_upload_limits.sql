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

do $$
declare
  v_avatar_buckets text[] := array['avatars', 'legacy_avatars'];
  v_photo_buckets text[] := array[
    'memory_photos',
    'vault_photos',
    'legacy_memory_photos',
    'legacy_vault_photos'
  ];
  v_voice_buckets text[] := array[
    'memory_voice',
    'vault_voice',
    'legacy_memory_voice',
    'legacy_vault_voice',
    'voice notes'
  ];
  v_image_mimes text[] := array[
    'image/heic',
    'image/heif',
    'image/jpeg',
    'image/png',
    'image/webp'
  ];
  v_audio_mimes text[] := array[
    'audio/aac',
    'audio/m4a',
    'audio/mp4',
    'audio/mpeg',
    'audio/ogg',
    'audio/wav',
    'audio/webm',
    'audio/x-m4a'
  ];
  v_expected text[];
  v_missing text[];
  v_bad_limits text[];
  v_bad_mimes text[];
begin
  v_expected := v_avatar_buckets || v_photo_buckets || v_voice_buckets;

  select coalesce(array_agg(expected.id order by expected.id), array[]::text[])
  into v_missing
  from unnest(v_expected) as expected(id)
  where not exists (
    select 1
    from storage.buckets b
    where b.id = expected.id
  );

  if cardinality(v_missing) > 0 then
    raise exception 'Missing storage bucket(s): %', array_to_string(v_missing, ', ')
      using errcode = 'P0001',
      detail = 'ERR_MEDIA_UPLOAD_LIMIT_BUCKET_MISSING';
  end if;

  select coalesce(
    array_agg(b.id || '=' || coalesce(b.file_size_limit::text, 'null') order by b.id),
    array[]::text[]
  )
  into v_bad_limits
  from storage.buckets b
  where (
    b.id = any(v_avatar_buckets)
    and b.file_size_limit is distinct from 5 * 1024 * 1024
  )
  or (
    b.id = any(v_photo_buckets)
    and b.file_size_limit is distinct from 12 * 1024 * 1024
  )
  or (
    b.id = any(v_voice_buckets)
    and b.file_size_limit is distinct from 25 * 1024 * 1024
  );

  if cardinality(v_bad_limits) > 0 then
    raise exception 'Incorrect storage upload limit(s): %', array_to_string(v_bad_limits, ', ')
      using errcode = 'P0001',
      detail = 'ERR_MEDIA_UPLOAD_LIMIT_SIZE_MISMATCH';
  end if;

  select coalesce(array_agg(b.id order by b.id), array[]::text[])
  into v_bad_mimes
  from storage.buckets b
  where (
    b.id = any((v_avatar_buckets || v_photo_buckets))
    and (
      not (coalesce(b.allowed_mime_types, array[]::text[]) @> v_image_mimes)
      or not (v_image_mimes @> coalesce(b.allowed_mime_types, array[]::text[]))
    )
  )
  or (
    b.id = any(v_voice_buckets)
    and (
      not (coalesce(b.allowed_mime_types, array[]::text[]) @> v_audio_mimes)
      or not (v_audio_mimes @> coalesce(b.allowed_mime_types, array[]::text[]))
    )
  );

  if cardinality(v_bad_mimes) > 0 then
    raise exception 'Incorrect storage MIME allow-list(s): %', array_to_string(v_bad_mimes, ', ')
      using errcode = 'P0001',
      detail = 'ERR_MEDIA_UPLOAD_LIMIT_MIME_MISMATCH';
  end if;
end;
$$;
