-- Fix-forward repairs for the initial EverRoot production migration.
--
-- These changes are non-destructive. They replace broken helper functions only:
-- - confirmed empty-family cleanup now iterates table names safely;
-- - legacy vault about/core media counts derive family ownership through the
--   legacy member id stored in vault_id;
-- - legacy vault media insert triggers use the same family lookup.

create or replace function public.count_family_rows_if_present(
  p_table_name text,
  p_family_id uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
begin
  if p_family_id is null then
    return 0;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = p_table_name
      and column_name = 'family_id'
  ) then
    execute format('select count(*) from public.%I where family_id = $1', p_table_name)
      into v_count
      using p_family_id;
  elsif p_table_name in ('legacy_vault_about_photos', 'legacy_vault_core_voice_note')
    and exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = p_table_name
        and column_name = 'vault_id'
    ) then
    execute format(
      'select count(*)
         from public.%I legacy_media
         join public.legacy_family_members lfm
           on lfm.id = legacy_media.vault_id
        where lfm.family_id = $1',
      p_table_name
    )
      into v_count
      using p_family_id;
  end if;

  return coalesce(v_count, 0);
end;
$$;

revoke all on function public.count_family_rows_if_present(text, uuid) from public;
grant execute on function public.count_family_rows_if_present(text, uuid) to service_role;

create or replace function public.destroy_empty_family_group_tree(p_family_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_table text;
begin
  if p_family_id is null then
    return;
  end if;

  perform pg_advisory_xact_lock(hashtext(p_family_id::text));

  perform 1
    from public.family_groups
   where id = p_family_id
   for update;

  if not found then
    return;
  end if;

  if exists (
    select 1
    from public.family_members
    where family_id = p_family_id
  ) then
    raise exception 'Family still has real members'
      using errcode = 'P0001',
            detail = 'ERR_FAMILY_NOT_EMPTY';
  end if;

  -- Do not delete vaults, normal memories, normal memory media, users, or auth
  -- rows. This clears only the now-empty family's tree/legacy scaffolding.
  update public.vaults
     set family_id = null
   where family_id = p_family_id;

  for v_table in
    select unnest(array[
      'family_invites',
      'family_relationships',
      'family_links',
      'legacy_memory_voice_notes',
      'legacy_memory_chunks',
      'legacy_memory_photos',
      'legacy_member_photos',
      'legacy_vault_about_photos',
      'legacy_vault_core_voice_note',
      'legacy_memories',
      'legacy_family_members'
    ]::text[])
  loop
    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = v_table
        and column_name = 'family_id'
    ) then
      execute format('delete from public.%I where family_id = $1', v_table)
        using p_family_id;
    elsif v_table in ('legacy_vault_about_photos', 'legacy_vault_core_voice_note')
      and exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = v_table
          and column_name = 'vault_id'
      ) then
      execute format(
        'delete from public.%I legacy_media
          where exists (
            select 1
              from public.legacy_family_members lfm
             where lfm.id = legacy_media.vault_id
               and lfm.family_id = $1
          )',
        v_table
      )
        using p_family_id;
    end if;
  end loop;

  delete from public.family_groups fg
   where fg.id = p_family_id
     and not exists (
       select 1
       from public.family_members fm
       where fm.family_id = p_family_id
     );
end;
$$;

revoke all on function public.destroy_empty_family_group_tree(uuid) from public;
grant execute on function public.destroy_empty_family_group_tree(uuid) to service_role;

create or replace function public.everroot_photo_count(
  p_family_id uuid,
  p_vault_id uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
begin
  if p_family_id is not null then
    select count(*)
      into v_count
      from public.vault_highlight_photos hp
      join public.vaults v on v.id = hp.vault_id
      join public.family_members fm
        on fm.user_id = v.owner_id
       and fm.family_id = p_family_id;

    if to_regclass('public.vault_about_photos') is not null then
      execute '
        select $1 + count(*)
        from public.vault_about_photos ap
        join public.vaults v on v.id = ap.vault_id
        join public.family_members fm
          on fm.user_id = v.owner_id
         and fm.family_id = $2'
        into v_count
        using v_count, p_family_id;
    end if;

    if to_regclass('public.memory_photos') is not null then
      execute '
        select $1 + count(*)
        from public.memory_photos mp
        join public.vaults v on v.id = mp.vault_id
        join public.family_members fm
          on fm.user_id = v.owner_id
         and fm.family_id = $2'
        into v_count
        using v_count, p_family_id;
    end if;

    if to_regclass('public.legacy_member_photos') is not null then
      execute 'select $1 + count(*) from public.legacy_member_photos where family_id = $2'
        into v_count
        using v_count, p_family_id;
    end if;

    if to_regclass('public.legacy_memory_photos') is not null then
      execute 'select $1 + count(*) from public.legacy_memory_photos where family_id = $2'
        into v_count
        using v_count, p_family_id;
    end if;

    if to_regclass('public.legacy_vault_about_photos') is not null then
      execute '
        select $1 + count(*)
        from public.legacy_vault_about_photos ap
        join public.legacy_family_members lfm on lfm.id = ap.vault_id
        where lfm.family_id = $2'
        into v_count
        using v_count, p_family_id;
    end if;

    return v_count;
  end if;

  select count(*)
    into v_count
    from public.vault_highlight_photos hp
   where hp.vault_id = p_vault_id;

  if to_regclass('public.vault_about_photos') is not null then
    execute 'select $1 + count(*) from public.vault_about_photos where vault_id = $2'
      into v_count
      using v_count, p_vault_id;
  end if;

  if to_regclass('public.memory_photos') is not null then
    execute 'select $1 + count(*) from public.memory_photos where vault_id = $2'
      into v_count
      using v_count, p_vault_id;
  end if;

  if to_regclass('public.legacy_vault_about_photos') is not null then
    execute 'select $1 + count(*) from public.legacy_vault_about_photos where vault_id = $2'
      into v_count
      using v_count, p_vault_id;
  end if;

  return v_count;
end;
$$;

create or replace function public.everroot_voice_note_count(
  p_family_id uuid,
  p_vault_id uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
begin
  if p_family_id is not null then
    if to_regclass('public.vault_core_voice_note') is not null then
      execute '
        select count(*)
        from public.vault_core_voice_note cv
        join public.vaults v on v.id = cv.vault_id
        join public.family_members fm
          on fm.user_id = v.owner_id
         and fm.family_id = $1'
        into v_count
        using p_family_id;
    end if;

    if to_regclass('public.memory_voice_notes') is not null then
      execute '
        select $1 + count(*)
        from public.memory_voice_notes mv
        join public.vaults v on v.id = mv.vault_id
        join public.family_members fm
          on fm.user_id = v.owner_id
         and fm.family_id = $2'
        into v_count
        using v_count, p_family_id;
    end if;

    if to_regclass('public.legacy_memory_voice_notes') is not null then
      execute 'select $1 + count(*) from public.legacy_memory_voice_notes where family_id = $2'
        into v_count
        using v_count, p_family_id;
    end if;

    if to_regclass('public.legacy_vault_core_voice_note') is not null then
      execute '
        select $1 + count(*)
        from public.legacy_vault_core_voice_note cv
        join public.legacy_family_members lfm on lfm.id = cv.vault_id
        where lfm.family_id = $2'
        into v_count
        using v_count, p_family_id;
    end if;

    return v_count;
  end if;

  if to_regclass('public.vault_core_voice_note') is not null then
    execute 'select count(*) from public.vault_core_voice_note where vault_id = $1'
      into v_count
      using p_vault_id;
  end if;

  if to_regclass('public.memory_voice_notes') is not null then
    execute 'select $1 + count(*) from public.memory_voice_notes where vault_id = $2'
      into v_count
      using v_count, p_vault_id;
  end if;

  if to_regclass('public.legacy_vault_core_voice_note') is not null then
    execute 'select $1 + count(*) from public.legacy_vault_core_voice_note where vault_id = $2'
      into v_count
      using v_count, p_vault_id;
  end if;

  return v_count;
end;
$$;

create or replace function public.everroot_assert_photo_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_family_id uuid;
  v_vault_id uuid;
  v_limit integer;
  v_count integer;
  v_lock_key text;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  v_vault_id := nullif(to_jsonb(new)->>'vault_id', '')::uuid;
  v_family_id := nullif(to_jsonb(new)->>'family_id', '')::uuid;

  if v_family_id is null
     and tg_table_name in ('legacy_vault_about_photos')
     and v_vault_id is not null then
    v_family_id := public.everroot_family_id_from_legacy_member(v_vault_id);
  end if;

  if v_family_id is null and v_vault_id is not null then
    v_family_id := public.everroot_family_for_vault(v_vault_id);
  end if;

  if v_family_id is null and (to_jsonb(new) ? 'legacy_member_id') then
    v_family_id := public.everroot_family_id_from_legacy_member(
      nullif(to_jsonb(new)->>'legacy_member_id', '')::uuid
    );
  end if;

  v_lock_key := coalesce(v_family_id::text, v_vault_id::text) || ':photos';
  perform pg_advisory_xact_lock(hashtext(v_lock_key));

  v_limit := public.everroot_limit_int(v_family_id, 'photos');
  v_count := public.everroot_photo_count(v_family_id, v_vault_id);

  if v_count >= v_limit then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_PHOTO_LIMIT',
      case public.everroot_family_plan(v_family_id)
        when 'everroot_family' then
          'This EverRoot Family has reached its photo allowance.'
        else
          'You''ve reached your EverRoot Free photo allowance.'
      end
    );
  end if;

  perform public.everroot_assert_storage_capacity(
    v_family_id,
    v_vault_id,
    to_jsonb(new)->>'path'
  );

  return new;
end;
$$;

create or replace function public.everroot_assert_voice_note_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_family_id uuid;
  v_vault_id uuid;
  v_limit integer;
  v_count integer;
  v_lock_key text;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  v_vault_id := nullif(to_jsonb(new)->>'vault_id', '')::uuid;
  v_family_id := nullif(to_jsonb(new)->>'family_id', '')::uuid;

  if v_family_id is null
     and tg_table_name in ('legacy_vault_core_voice_note')
     and v_vault_id is not null then
    v_family_id := public.everroot_family_id_from_legacy_member(v_vault_id);
  end if;

  if v_family_id is null and v_vault_id is not null then
    v_family_id := public.everroot_family_for_vault(v_vault_id);
  end if;

  if v_family_id is null and (to_jsonb(new) ? 'legacy_member_id') then
    v_family_id := public.everroot_family_id_from_legacy_member(
      nullif(to_jsonb(new)->>'legacy_member_id', '')::uuid
    );
  end if;

  v_lock_key := coalesce(v_family_id::text, v_vault_id::text) || ':voice_notes';
  perform pg_advisory_xact_lock(hashtext(v_lock_key));

  v_limit := public.everroot_limit_int(v_family_id, 'voice_notes');
  v_count := public.everroot_voice_note_count(v_family_id, v_vault_id);

  if v_count >= v_limit then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_VOICE_LIMIT',
      case public.everroot_family_plan(v_family_id)
        when 'everroot_family' then
          'This EverRoot Family has reached its voice-note allowance.'
        else
          'You''ve reached your EverRoot Free voice-note allowance.'
      end
    );
  end if;

  perform public.everroot_assert_storage_capacity(
    v_family_id,
    v_vault_id,
    to_jsonb(new)->>'path'
  );

  return new;
end;
$$;

revoke all on function public.everroot_photo_count(uuid, uuid) from public, anon;
revoke all on function public.everroot_voice_note_count(uuid, uuid) from public, anon;
revoke all on function public.everroot_assert_photo_capacity() from public, anon;
revoke all on function public.everroot_assert_voice_note_capacity() from public, anon;
