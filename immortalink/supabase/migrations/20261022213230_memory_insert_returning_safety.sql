-- INSERT ... RETURNING checks SELECT policies before a STABLE helper can see
-- the newly inserted memory. Use the candidate row instead of rereading it.
-- Vault visibility retains contributor/block restrictions; the second check
-- retains exact-memory restrictions. Existing ownership/write policies stay intact.
alter policy safety_memory_read on public.memories
  using (
    content_safety.vault_visible(vault_id)
    and content_safety.visible('memory', id)
  );
