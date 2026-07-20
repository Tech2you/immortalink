create table if not exists public.vault_highlight_photos (
  id uuid primary key default gen_random_uuid(),
  vault_id uuid not null references public.vaults(id) on delete cascade,
  path text not null unique,
  created_at timestamptz not null default now()
);

create index if not exists vault_highlight_photos_vault_created_idx
  on public.vault_highlight_photos (vault_id, created_at desc);

alter table public.vault_highlight_photos enable row level security;

drop policy if exists "vault owners manage highlight photos"
  on public.vault_highlight_photos;
create policy "vault owners manage highlight photos"
  on public.vault_highlight_photos
  for all
  to authenticated
  using (
    exists (
      select 1
      from public.vaults v
      where v.id = vault_id
        and v.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.vaults v
      where v.id = vault_id
        and v.owner_id = auth.uid()
    )
  );

drop policy if exists "family members can view highlight photos"
  on public.vault_highlight_photos;
create policy "family members can view highlight photos"
  on public.vault_highlight_photos
  for select
  to authenticated
  using (public.shares_family_with_vault(vault_id));

-- Register highlights that pre-date this table. This keeps existing photos
-- visible to relatives without changing their storage paths.
insert into public.vault_highlight_photos (vault_id, path, created_at)
select
  v.id,
  o.name,
  coalesce(o.created_at, now())
from storage.objects o
join public.vaults v
  on v.id::text = (storage.foldername(o.name))[2]
where o.bucket_id = 'vault_photos'
  and (storage.foldername(o.name))[3] = 'featured'
on conflict (path) do nothing;
