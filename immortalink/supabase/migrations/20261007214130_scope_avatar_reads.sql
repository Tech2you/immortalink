-- Keep own-folder, family-vault and verified legacy-reference reads. Remove
-- the older policy that lets unrelated authenticated accounts read any avatar.
drop policy if exists avatars_read_auth on storage.objects;
