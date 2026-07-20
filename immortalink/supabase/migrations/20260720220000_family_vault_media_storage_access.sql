-- Authenticated relatives who share a family with a vault may read that
-- vault's private media. Object paths use: owner_id/vault_id/...
drop policy if exists "family members can read shared vault media"
  on storage.objects;

create policy "family members can read shared vault media"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id in (
      'vault_photos',
      'vault_voice',
      'memory_photos',
      'memory_voice'
    )
    and exists (
      select 1
      from public.vaults v
      where v.id::text = (storage.foldername(name))[2]
        and public.shares_family_with_vault(v.id)
    )
  );
