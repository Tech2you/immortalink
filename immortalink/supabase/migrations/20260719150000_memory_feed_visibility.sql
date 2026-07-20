-- Memories are shared to the family feed by default, while each author can
-- keep an individual memory off the feed without removing it from the vault.
alter table public.memories
  add column if not exists share_to_family_feed boolean not null default true;

create index if not exists memories_family_feed_visibility_idx
  on public.memories (vault_id, share_to_family_feed, created_at desc);
