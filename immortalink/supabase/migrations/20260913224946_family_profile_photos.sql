-- One bounded private image per family; existing email and vault media are untouched.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('family_avatars', 'family_avatars', false, 5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do nothing;

create policy family_avatar_members on storage.objects
for all to authenticated
using (
  bucket_id = 'family_avatars' and exists (
    select 1 from public.family_members fm
    where fm.user_id = (select auth.uid())
      and storage.objects.name = fm.family_id::text || '/avatar'
  )
)
with check (
  bucket_id = 'family_avatars' and exists (
    select 1 from public.family_members fm
    where fm.user_id = (select auth.uid())
      and storage.objects.name = fm.family_id::text || '/avatar'
  )
);
