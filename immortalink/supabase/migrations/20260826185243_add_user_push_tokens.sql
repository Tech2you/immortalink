create table if not exists public.user_push_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  platform text not null default 'ios',
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists user_push_tokens_user_id_idx
  on public.user_push_tokens (user_id);

alter table public.user_push_tokens enable row level security;

drop policy if exists "Users can manage their own push tokens"
  on public.user_push_tokens;

create policy "Users can manage their own push tokens"
  on public.user_push_tokens
  for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on public.user_push_tokens from anon;
grant select, insert, update, delete on public.user_push_tokens to authenticated;
