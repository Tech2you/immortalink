-- Legacy galleries are stored in vault_photos, but belong to legacy profiles,
-- not personal vault IDs encoded in the second path segment.
create function public.can_read_legacy_gallery_object(p_bucket text,p_name text)
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select auth.uid() is not null and exists (
    select 1 from public.legacy_family_members l
    join public.family_members fm on fm.family_id=l.family_id and fm.user_id=auth.uid()
    where (p_bucket='avatars' and l.avatar_path=p_name)
       or (p_bucket='vault_photos' and (
         exists(select 1 from public.legacy_member_photos p where p.legacy_member_id=l.id and p.path=p_name)
         or exists(select 1 from public.legacy_memory_photos p where p.legacy_member_id=l.id and p.path=p_name)
       ))
  );
$$;
revoke all on function public.can_read_legacy_gallery_object(text,text) from public,anon;
grant execute on function public.can_read_legacy_gallery_object(text,text) to authenticated;
create policy legacy_gallery_reference_read on storage.objects for select to authenticated
  using(public.can_read_legacy_gallery_object(bucket_id,name));
create index if not exists legacy_member_photos_path_idx on public.legacy_member_photos(path);
create index if not exists legacy_memory_photos_path_idx on public.legacy_memory_photos(path);
