create table if not exists public.legacy_memory_voice_notes (
  id uuid primary key default gen_random_uuid(),
  legacy_memory_id uuid references public.legacy_memories(id) on delete cascade,
  legacy_member_id uuid references public.legacy_family_members(id) on delete cascade,
  family_id uuid,
  path text,
  title text default 'Voice note',
  transcript text,
  created_at timestamptz not null default now()
);

alter table public.legacy_memory_voice_notes
  add column if not exists legacy_memory_id uuid references public.legacy_memories(id) on delete cascade,
  add column if not exists legacy_member_id uuid references public.legacy_family_members(id) on delete cascade,
  add column if not exists family_id uuid,
  add column if not exists path text,
  add column if not exists title text default 'Voice note',
  add column if not exists transcript text,
  add column if not exists created_at timestamptz not null default now();

update public.legacy_memory_voice_notes lmv
set
  legacy_member_id = coalesce(lmv.legacy_member_id, lm.legacy_member_id),
  family_id = coalesce(lmv.family_id, lm.family_id),
  title = coalesce(nullif(lmv.title, ''), 'Voice note')
from public.legacy_memories lm
where lmv.legacy_memory_id = lm.id
  and (
    lmv.legacy_member_id is null
    or lmv.family_id is null
    or lmv.title is null
    or lmv.title = ''
  );

create index if not exists legacy_memory_voice_notes_memory_idx
  on public.legacy_memory_voice_notes (legacy_memory_id, created_at desc);

alter table public.legacy_memory_voice_notes enable row level security;

drop policy if exists "family members can view legacy memory voice"
  on public.legacy_memory_voice_notes;
create policy "family members can view legacy memory voice"
  on public.legacy_memory_voice_notes
  for select to authenticated
  using (
    exists (
      select 1
      from public.family_members fm
      where fm.family_id = legacy_memory_voice_notes.family_id
        and fm.user_id = auth.uid()
    )
  );

drop policy if exists "family members can add legacy memory voice"
  on public.legacy_memory_voice_notes;
create policy "family members can add legacy memory voice"
  on public.legacy_memory_voice_notes
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.family_members fm
      where fm.family_id = legacy_memory_voice_notes.family_id
        and fm.user_id = auth.uid()
    )
  );

drop policy if exists "family members can remove legacy memory voice"
  on public.legacy_memory_voice_notes;
create policy "family members can remove legacy memory voice"
  on public.legacy_memory_voice_notes
  for delete to authenticated
  using (
    exists (
      select 1
      from public.family_members fm
      where fm.family_id = legacy_memory_voice_notes.family_id
        and fm.user_id = auth.uid()
    )
  );

create or replace function public.can_read_shared_media_object(
  p_bucket_id text,
  p_name text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_vault_id uuid;
  v_family_id uuid;
  v_path_vault_id text;
begin
  if auth.uid() is null then
    return false;
  end if;

  case p_bucket_id
    when 'vault_photos' then
      select media.vault_id
      into v_vault_id
      from (
        select hp.vault_id
        from public.vault_highlight_photos hp
        where hp.path = p_name

        union all

        select ap.vault_id
        from public.vault_about_photos ap
        where ap.path = p_name
      ) media
      limit 1;

    when 'vault_voice' then
      select cv.vault_id
      into v_vault_id
      from public.vault_core_voice_note cv
      where cv.path = p_name
      limit 1;

    when 'memory_photos' then
      select mp.vault_id
      into v_vault_id
      from public.memory_photos mp
      where mp.path = p_name
      limit 1;

    when 'memory_voice' then
      select mv.vault_id
      into v_vault_id
      from public.memory_voice_notes mv
      where mv.path = p_name
      limit 1;

      if v_vault_id is null then
        select lmv.family_id
        into v_family_id
        from public.legacy_memory_voice_notes lmv
        where lmv.path = p_name
        limit 1;
      end if;

    else
      return false;
  end case;

  if v_family_id is not null then
    return exists (
      select 1
      from public.family_members fm
      where fm.family_id = v_family_id
        and fm.user_id = auth.uid()
    );
  end if;

  -- Older media can pre-date its metadata table. All supported object paths
  -- use owner_id/vault_id/..., so resolve that vault only when it is a UUID.
  if v_vault_id is null then
    v_path_vault_id := split_part(p_name, '/', 2);
    if v_path_vault_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_vault_id := v_path_vault_id::uuid;
    end if;
  end if;

  return v_vault_id is not null
    and public.shares_family_with_vault(v_vault_id);
end;
$$;

revoke all on function public.can_read_shared_media_object(text, text)
  from public;
grant execute on function public.can_read_shared_media_object(text, text)
  to authenticated;
