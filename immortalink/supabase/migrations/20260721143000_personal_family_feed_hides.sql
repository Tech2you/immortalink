create table if not exists public.family_feed_hidden_vaults (
  user_id uuid not null references auth.users(id) on delete cascade,
  hidden_vault_id uuid not null references public.vaults(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, hidden_vault_id)
);

alter table public.family_feed_hidden_vaults enable row level security;

drop policy if exists "Users can view their own hidden feed vaults"
  on public.family_feed_hidden_vaults;
create policy "Users can view their own hidden feed vaults"
  on public.family_feed_hidden_vaults
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can hide vaults from their own feed"
  on public.family_feed_hidden_vaults;
create policy "Users can hide vaults from their own feed"
  on public.family_feed_hidden_vaults
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can restore vaults to their own feed"
  on public.family_feed_hidden_vaults;
create policy "Users can restore vaults to their own feed"
  on public.family_feed_hidden_vaults
  for delete
  to authenticated
  using (auth.uid() = user_id);

grant select, insert, delete
  on table public.family_feed_hidden_vaults
  to authenticated;
