-- Fix-forward: legacy vault media tables differ across environments.
--
-- Some legacy media tables are keyed by legacy_member_id rather than family_id
-- or vault_id. These helpers detect the available key column before counting or
-- deleting, so quota and confirmed-cleanup logic stays compatible.

create or replace function public.everroot_legacy_media_count(
  p_table_name text,
  p_family_id uuid,
  p_legacy_member_id uuid default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
  v_key_column text;
begin
  if p_table_name not in (
    'legacy_vault_about_photos',
    'legacy_vault_core_voice_note'
  ) then
    return 0;
  end if;

  if to_regclass(format('public.%I', p_table_name)) is null then
    return 0;
  end if;

  select c.column_name
    into v_key_column
    from information_schema.columns c
   where c.table_schema = 'public'
     and c.table_name = p_table_name
     and c.column_name in ('family_id', 'legacy_member_id', 'vault_id')
   order by case c.column_name
     when 'family_id' then 1
     when 'legacy_member_id' then 2
     when 'vault_id' then 3
     else 4
   end
   limit 1;

  if v_key_column is null then
    return 0;
  end if;

  if p_family_id is not null then
    if v_key_column = 'family_id' then
      execute format('select count(*) from public.%I where family_id = $1', p_table_name)
        into v_count
        using p_family_id;
    else
      execute format(
        'select count(*)
           from public.%I legacy_media
           join public.legacy_family_members lfm
             on lfm.id = legacy_media.%I
          where lfm.family_id = $1',
        p_table_name,
        v_key_column
      )
        into v_count
        using p_family_id;
    end if;

    return coalesce(v_count, 0);
  end if;

  if p_legacy_member_id is not null and v_key_column in ('legacy_member_id', 'vault_id') then
    execute format('select count(*) from public.%I where %I = $1', p_table_name, v_key_column)
      into v_count
      using p_legacy_member_id;
  end if;

  return coalesce(v_count, 0);
end;
$$;

revoke all on function public.everroot_legacy_media_count(text, uuid, uuid) from public, anon;

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

  if p_table_name in ('legacy_vault_about_photos', 'legacy_vault_core_voice_note') then
    return public.everroot_legacy_media_count(p_table_name, p_family_id);
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
  v_key_column text;
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
    elsif v_table in ('legacy_vault_about_photos', 'legacy_vault_core_voice_note') then
      select c.column_name
        into v_key_column
        from information_schema.columns c
       where c.table_schema = 'public'
         and c.table_name = v_table
         and c.column_name in ('legacy_member_id', 'vault_id')
       order by case c.column_name
         when 'legacy_member_id' then 1
         when 'vault_id' then 2
         else 3
       end
       limit 1;

      if v_key_column is not null then
        execute format(
          'delete from public.%I legacy_media
            where exists (
              select 1
                from public.legacy_family_members lfm
               where lfm.id = legacy_media.%I
                 and lfm.family_id = $1
            )',
          v_table,
          v_key_column
        )
          using p_family_id;
      end if;
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

    v_count := v_count
      + public.everroot_legacy_media_count('legacy_vault_about_photos', p_family_id);

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

  v_count := v_count
    + public.everroot_legacy_media_count('legacy_vault_about_photos', null, p_vault_id);

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

    v_count := v_count
      + public.everroot_legacy_media_count('legacy_vault_core_voice_note', p_family_id);

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

  v_count := v_count
    + public.everroot_legacy_media_count('legacy_vault_core_voice_note', null, p_vault_id);

  return v_count;
end;
$$;

revoke all on function public.everroot_photo_count(uuid, uuid) from public, anon;
revoke all on function public.everroot_voice_note_count(uuid, uuid) from public, anon;
