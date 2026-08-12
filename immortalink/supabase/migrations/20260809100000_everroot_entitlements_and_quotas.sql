-- EverRoot launch entitlement and quota foundation.
--
-- This migration is intentionally additive:
-- - no existing user, vault, family, memory, legacy person, or media row is
--   deleted;
-- - users already above a new quota keep existing content;
-- - new inserts that would exceed the applicable plan limit are blocked.

create table if not exists public.family_entitlements (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.family_groups(id) on delete cascade,
  plan text not null default 'free',
  status text not null default 'free',
  provider text,
  provider_customer_id text,
  provider_entitlement_id text,
  provider_subscription_id text,
  billing_owner_user_id uuid references auth.users(id) on delete set null,
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint family_entitlements_plan_check
    check (plan in ('free', 'everroot_family')),
  constraint family_entitlements_status_check
    check (status in ('free', 'active', 'grace_period', 'expired', 'cancelled'))
);

create unique index if not exists family_entitlements_family_unique
  on public.family_entitlements(family_id);

alter table public.family_entitlements enable row level security;

drop policy if exists "family members can view family entitlements"
  on public.family_entitlements;
create policy "family members can view family entitlements"
  on public.family_entitlements
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.family_members fm
      where fm.family_id = family_entitlements.family_id
        and fm.user_id = auth.uid()
    )
  );

create table if not exists public.everroot_ai_usage_periods (
  id uuid primary key default gen_random_uuid(),
  scope_type text not null,
  scope_id uuid not null,
  period_start date not null,
  used_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint everroot_ai_usage_scope_type_check
    check (scope_type in ('user', 'family')),
  constraint everroot_ai_usage_used_count_check
    check (used_count >= 0)
);

create unique index if not exists everroot_ai_usage_periods_scope_period_unique
  on public.everroot_ai_usage_periods(scope_type, scope_id, period_start);

alter table public.everroot_ai_usage_periods enable row level security;

create table if not exists public.everroot_invite_usage_periods (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.family_groups(id) on delete cascade,
  period_start date not null,
  used_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint everroot_invite_usage_used_count_check
    check (used_count >= 0)
);

create unique index if not exists everroot_invite_usage_periods_family_period_unique
  on public.everroot_invite_usage_periods(family_id, period_start);

alter table public.everroot_invite_usage_periods enable row level security;

drop policy if exists "users can view their own everroot ai usage"
  on public.everroot_ai_usage_periods;
create policy "users can view their own everroot ai usage"
  on public.everroot_ai_usage_periods
  for select
  to authenticated
  using (
    (scope_type = 'user' and scope_id = auth.uid())
    or (
      scope_type = 'family'
      and exists (
        select 1
        from public.family_members fm
        where fm.family_id = everroot_ai_usage_periods.scope_id
          and fm.user_id = auth.uid()
      )
    )
  );

drop policy if exists "family members can view everroot invite usage"
  on public.everroot_invite_usage_periods;
create policy "family members can view everroot invite usage"
  on public.everroot_invite_usage_periods
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.family_members fm
      where fm.family_id = everroot_invite_usage_periods.family_id
        and fm.user_id = auth.uid()
    )
  );

create or replace function public.everroot_touch_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists family_entitlements_touch_updated_at
  on public.family_entitlements;
create trigger family_entitlements_touch_updated_at
  before update on public.family_entitlements
  for each row
  execute function public.everroot_touch_updated_at();

drop trigger if exists everroot_ai_usage_periods_touch_updated_at
  on public.everroot_ai_usage_periods;
create trigger everroot_ai_usage_periods_touch_updated_at
  before update on public.everroot_ai_usage_periods
  for each row
  execute function public.everroot_touch_updated_at();

drop trigger if exists everroot_invite_usage_periods_touch_updated_at
  on public.everroot_invite_usage_periods;
create trigger everroot_invite_usage_periods_touch_updated_at
  before update on public.everroot_invite_usage_periods
  for each row
  execute function public.everroot_touch_updated_at();

create or replace function public.everroot_family_plan(p_family_id uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when fe.plan = 'everroot_family'
       and fe.status in ('active', 'grace_period')
       and (
         fe.current_period_end is null
         or fe.current_period_end > now()
       )
      then 'everroot_family'
      else 'free'
    end
    from public.family_entitlements fe
    where fe.family_id = p_family_id
    limit 1
  ), 'free');
$$;

create or replace function public.everroot_limits(p_family_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case public.everroot_family_plan(p_family_id)
    when 'everroot_family' then jsonb_build_object(
      'plan', 'everroot_family',
      'real_members', 8,
      'legacy_people', 100,
      'memories', 1000,
      'photos', 2000,
      'voice_notes', 500,
      'storage_bytes', 10737418240,
      'ai_responses_monthly', 500,
      'invites_monthly', 50,
      'voice_seconds', 120
    )
    else jsonb_build_object(
      'plan', 'free',
      'real_members', 1,
      'legacy_people', 8,
      'memories', 100,
      'photos', 100,
      'voice_notes', 25,
      'storage_bytes', 524288000,
      'ai_responses_monthly', 20,
      'invites_monthly', 0,
      'voice_seconds', 120
    )
  end;
$$;

create or replace function public.everroot_limit_int(
  p_family_id uuid,
  p_key text
)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (public.everroot_limits(p_family_id)->>p_key)::integer;
$$;

create or replace function public.everroot_limit_bigint(
  p_family_id uuid,
  p_key text
)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (public.everroot_limits(p_family_id)->>p_key)::bigint;
$$;

create or replace function public.everroot_quota_error(
  p_code text,
  p_message text
)
returns void
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  raise exception '%', p_message
    using errcode = 'P0001',
          detail = p_code;
end;
$$;

create or replace function public.everroot_family_for_vault(p_vault_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select v.family_id
  from public.vaults v
  where v.id = p_vault_id;
$$;

create or replace function public.everroot_assert_can_add_family_member(
  p_family_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_plan text;
  v_limit integer;
  v_count integer;
begin
  if p_family_id is null or p_user_id is null then
    return;
  end if;

  perform pg_advisory_xact_lock(hashtext(p_family_id::text || ':members'));

  v_plan := public.everroot_family_plan(p_family_id);

  if v_plan = 'free' and exists (
    select 1
    from public.family_members fm
    where fm.user_id = p_user_id
      and fm.family_id <> p_family_id
      and public.everroot_family_plan(fm.family_id) = 'free'
  ) then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_FREE_FAMILY_LIMIT',
      'EverRoot Free includes one personal family tree. Start EverRoot Family to create or join another family tree.'
    );
  end if;

  v_limit := public.everroot_limit_int(p_family_id, 'real_members');

  select count(*)
    into v_count
    from public.family_members fm
   where fm.family_id = p_family_id;

  if v_count >= v_limit then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_MEMBER_LIMIT',
      case v_plan
        when 'everroot_family' then
          'This EverRoot Family already has 8 real family accounts.'
        else
          'EverRoot Free includes one personal account. Start EverRoot Family to invite relatives.'
      end
    );
  end if;
end;
$$;

create or replace function public.everroot_assert_family_member_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  perform public.everroot_assert_can_add_family_member(new.family_id, new.user_id);

  return new;
end;
$$;

drop trigger if exists everroot_family_member_capacity_before_insert
  on public.family_members;
create trigger everroot_family_member_capacity_before_insert
  before insert on public.family_members
  for each row
  execute function public.everroot_assert_family_member_capacity();

create or replace function public.everroot_assert_invite_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_plan text;
  v_limit integer;
  v_used integer;
  v_period date := date_trunc('month', now())::date;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext(new.family_id::text || ':invites'));

  v_plan := public.everroot_family_plan(new.family_id);
  v_limit := public.everroot_limit_int(new.family_id, 'invites_monthly');

  if v_plan <> 'everroot_family' then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_FAMILY_REQUIRED',
      'Start EverRoot Family to invite relatives into your family tree.'
    );
  end if;

  if exists (
    select 1
    from public.family_invites fi
    where fi.family_id = new.family_id
      and fi.created_by = new.created_by
      and fi.created_at > now() - interval '10 seconds'
  ) then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_INVITE_COOLDOWN',
      'Please wait a moment before creating another invite.'
    );
  end if;

  insert into public.everroot_invite_usage_periods (
    family_id,
    period_start,
    used_count
  ) values (
    new.family_id,
    v_period,
    0
  )
  on conflict (family_id, period_start) do nothing;

  select used_count
    into v_used
    from public.everroot_invite_usage_periods
   where family_id = new.family_id
     and period_start = v_period
   for update;

  if coalesce(v_used, 0) >= v_limit then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_INVITE_LIMIT',
      'This EverRoot Family has used this month''s invite allowance.'
    );
  end if;

  update public.everroot_invite_usage_periods
     set used_count = used_count + 1
   where family_id = new.family_id
     and period_start = v_period;

  return new;
end;
$$;

drop trigger if exists everroot_invite_capacity_before_insert
  on public.family_invites;
create trigger everroot_invite_capacity_before_insert
  before insert on public.family_invites
  for each row
  execute function public.everroot_assert_invite_capacity();

create or replace function public.everroot_assert_legacy_person_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit integer;
  v_count integer;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext(new.family_id::text || ':legacy_people'));

  v_limit := public.everroot_limit_int(new.family_id, 'legacy_people');

  select count(*)
    into v_count
    from public.legacy_family_members lfm
   where lfm.family_id = new.family_id
     and coalesce(lfm.replaced_by_vault_id::text, '') = '';

  if v_count >= v_limit then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_LEGACY_LIMIT',
      case public.everroot_family_plan(new.family_id)
        when 'everroot_family' then
          'This EverRoot Family has reached its Legacy People allowance.'
        else
          'You''ve added 8 Legacy People on EverRoot Free. EverRoot Family gives your family room to grow together.'
      end
    );
  end if;

  return new;
end;
$$;

drop trigger if exists everroot_legacy_person_capacity_before_insert
  on public.legacy_family_members;
create trigger everroot_legacy_person_capacity_before_insert
  before insert on public.legacy_family_members
  for each row
  execute function public.everroot_assert_legacy_person_capacity();

create or replace function public.everroot_memory_count(
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
      from public.memories m
      join public.vaults v on v.id = m.vault_id
      join public.family_members fm
        on fm.user_id = v.owner_id
       and fm.family_id = p_family_id;

    if to_regclass('public.legacy_memories') is not null then
      execute 'select $1 + count(*) from public.legacy_memories where family_id = $2'
        into v_count
        using v_count, p_family_id;
    end if;

    return v_count;
  end if;

  select count(*)
    into v_count
    from public.memories m
   where m.vault_id = p_vault_id;

  return v_count;
end;
$$;

create or replace function public.everroot_assert_memory_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_family_id uuid;
  v_limit integer;
  v_count integer;
  v_lock_key text;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  v_family_id := public.everroot_family_for_vault(new.vault_id);
  v_lock_key := coalesce(v_family_id::text, new.vault_id::text) || ':memories';
  perform pg_advisory_xact_lock(hashtext(v_lock_key));

  v_limit := public.everroot_limit_int(v_family_id, 'memories');
  v_count := public.everroot_memory_count(v_family_id, new.vault_id);

  if v_count >= v_limit then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_MEMORY_LIMIT',
      case public.everroot_family_plan(v_family_id)
        when 'everroot_family' then
          'This EverRoot Family has reached its memory allowance.'
        else
          'You''ve reached your EverRoot Free memory allowance.'
      end
    );
  end if;

  return new;
end;
$$;

drop trigger if exists everroot_memory_capacity_before_insert
  on public.memories;
create trigger everroot_memory_capacity_before_insert
  before insert on public.memories
  for each row
  execute function public.everroot_assert_memory_capacity();

create or replace function public.everroot_assert_legacy_memory_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit integer;
  v_count integer;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext(new.family_id::text || ':memories'));

  v_limit := public.everroot_limit_int(new.family_id, 'memories');
  v_count := public.everroot_memory_count(new.family_id, null);

  if v_count >= v_limit then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_MEMORY_LIMIT',
      case public.everroot_family_plan(new.family_id)
        when 'everroot_family' then
          'This EverRoot Family has reached its memory allowance.'
        else
          'You''ve reached your EverRoot Free memory allowance.'
      end
    );
  end if;

  return new;
end;
$$;

do $$
begin
  if to_regclass('public.legacy_memories') is not null then
    execute 'drop trigger if exists everroot_legacy_memory_capacity_before_insert on public.legacy_memories';
    execute 'create trigger everroot_legacy_memory_capacity_before_insert
      before insert on public.legacy_memories
      for each row
      execute function public.everroot_assert_legacy_memory_capacity()';
  end if;
end
$$;

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
      execute 'select $1 + count(*) from public.legacy_vault_about_photos where family_id = $2'
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
      execute 'select $1 + count(*) from public.legacy_vault_core_voice_note where family_id = $2'
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

  return v_count;
end;
$$;

create or replace function public.everroot_family_id_from_legacy_member(
  p_legacy_member_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select lfm.family_id
  from public.legacy_family_members lfm
  where lfm.id = p_legacy_member_id;
$$;

create or replace function public.everroot_media_bucket_ids()
returns text[]
language sql
stable
set search_path = public, pg_temp
as $$
  select array[
    'avatars',
    'legacy_avatars',
    'legacy_memory_photos',
    'legacy_memory_voice',
    'legacy_vault_photos',
    'legacy_vault_voice',
    'memory_photos',
    'memory_voice',
    'vault_photos',
    'vault_voice',
    'voice notes'
  ]::text[];
$$;

create or replace function public.everroot_storage_metadata_size(
  p_metadata jsonb
)
returns bigint
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when p_metadata ? 'size'
     and (p_metadata->>'size') ~ '^[0-9]+$'
    then (p_metadata->>'size')::bigint
    else 0
  end;
$$;

create or replace function public.everroot_try_uuid(p_value text)
returns uuid
language plpgsql
immutable
set search_path = public, pg_temp
as $$
begin
  return nullif(p_value, '')::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

create or replace function public.everroot_storage_bytes_used(
  p_family_id uuid,
  p_vault_id uuid
)
returns bigint
language plpgsql
stable
security definer
set search_path = public, storage, pg_temp
as $$
declare
  v_user_id uuid;
  v_total bigint := 0;
begin
  if p_family_id is not null then
    select coalesce(sum(public.everroot_storage_metadata_size(o.metadata)), 0)
      into v_total
      from storage.objects o
     where o.bucket_id = any(public.everroot_media_bucket_ids())
       and (
         exists (
           select 1
           from public.vaults v
           join public.family_members fm
             on fm.user_id = v.owner_id
            and fm.family_id = p_family_id
          where (storage.foldername(o.name))[1] = v.owner_id::text
            and (storage.foldername(o.name))[2] = v.id::text
         )
         or (storage.foldername(o.name))[2] = p_family_id::text
       );

    return v_total;
  end if;

  if p_vault_id is null then
    return 0;
  end if;

  select owner_id
    into v_user_id
    from public.vaults
   where id = p_vault_id;

  select coalesce(sum(public.everroot_storage_metadata_size(o.metadata)), 0)
    into v_total
    from storage.objects o
   where o.bucket_id = any(public.everroot_media_bucket_ids())
     and (storage.foldername(o.name))[1] = v_user_id::text
     and (storage.foldername(o.name))[2] = p_vault_id::text;

  return v_total;
end;
$$;

create or replace function public.everroot_assert_storage_object_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, storage, pg_temp
as $$
declare
  v_folders text[];
  v_owner_id uuid;
  v_slot_id uuid;
  v_family_id uuid;
  v_vault_id uuid;
  v_limit bigint;
  v_used bigint;
  v_new_size bigint;
  v_old_size bigint := 0;
  v_adjusted_used bigint;
  v_lock_key text;
begin
  if new.bucket_id <> all(public.everroot_media_bucket_ids()) then
    return new;
  end if;

  v_folders := storage.foldername(new.name);
  v_owner_id := public.everroot_try_uuid(v_folders[1]);
  v_slot_id := public.everroot_try_uuid(v_folders[2]);

  if v_owner_id is null or v_slot_id is null then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_STORAGE_PATH',
      'This media upload path is not valid for EverRoot storage.'
    );
  end if;

  select v.id, v.family_id
    into v_vault_id, v_family_id
    from public.vaults v
   where v.id = v_slot_id
     and v.owner_id = v_owner_id
   limit 1;

  if v_vault_id is null then
    select fg.id
      into v_family_id
      from public.family_groups fg
     where fg.id = v_slot_id
     limit 1;
  end if;

  if v_vault_id is null and v_family_id is null then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_STORAGE_PATH',
      'This media upload path is not linked to an EverRoot vault or family.'
    );
  end if;

  v_lock_key := coalesce(v_family_id::text, v_vault_id::text) || ':storage';
  perform pg_advisory_xact_lock(hashtext(v_lock_key));

  v_limit := public.everroot_limit_bigint(v_family_id, 'storage_bytes');
  v_used := public.everroot_storage_bytes_used(v_family_id, v_vault_id);
  v_new_size := public.everroot_storage_metadata_size(new.metadata);

  if tg_op = 'UPDATE'
     and old.bucket_id = new.bucket_id
     and old.name = new.name then
    v_old_size := public.everroot_storage_metadata_size(old.metadata);
  end if;

  v_adjusted_used := greatest(v_used - v_old_size, 0) + v_new_size;

  if v_adjusted_used > v_limit then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_STORAGE_LIMIT',
      case public.everroot_family_plan(v_family_id)
        when 'everroot_family' then
          'This EverRoot Family has reached its storage allowance.'
        else
          'You''ve reached your EverRoot Free storage allowance.'
      end
    );
  end if;

  return new;
end;
$$;

drop trigger if exists everroot_storage_object_capacity_before_write
  on storage.objects;
create trigger everroot_storage_object_capacity_before_write
  before insert or update on storage.objects
  for each row
  execute function public.everroot_assert_storage_object_capacity();

create or replace function public.everroot_assert_storage_capacity(
  p_family_id uuid,
  p_vault_id uuid,
  p_path text
)
returns void
language plpgsql
security definer
set search_path = public, storage, pg_temp
as $$
declare
  v_limit bigint;
  v_used bigint;
  v_lock_key text;
begin
  if nullif(p_path, '') is null then
    return;
  end if;

  v_lock_key := coalesce(p_family_id::text, p_vault_id::text) || ':storage';
  perform pg_advisory_xact_lock(hashtext(v_lock_key));

  v_limit := public.everroot_limit_bigint(p_family_id, 'storage_bytes');
  v_used := public.everroot_storage_bytes_used(p_family_id, p_vault_id);

  if v_used > v_limit then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_STORAGE_LIMIT',
      case public.everroot_family_plan(p_family_id)
        when 'everroot_family' then
          'This EverRoot Family has reached its storage allowance.'
        else
          'You''ve reached your EverRoot Free storage allowance.'
      end
    );
  end if;
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

create or replace function public.everroot_assert_vault_avatar_storage_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, storage, pg_temp
as $$
begin
  if tg_op = 'UPDATE'
     and coalesce(new.avatar_path, '') = coalesce(old.avatar_path, '') then
    return new;
  end if;

  perform public.everroot_assert_storage_capacity(
    new.family_id,
    new.id,
    new.avatar_path
  );

  return new;
end;
$$;

drop trigger if exists everroot_vault_avatar_storage_before_write
  on public.vaults;
create trigger everroot_vault_avatar_storage_before_write
  before insert or update of avatar_path on public.vaults
  for each row
  execute function public.everroot_assert_vault_avatar_storage_capacity();

create or replace function public.everroot_assert_legacy_avatar_storage_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, storage, pg_temp
as $$
begin
  if tg_op = 'UPDATE'
     and coalesce(new.avatar_path, '') = coalesce(old.avatar_path, '') then
    return new;
  end if;

  perform public.everroot_assert_storage_capacity(
    new.family_id,
    null,
    new.avatar_path
  );

  return new;
end;
$$;

drop trigger if exists everroot_legacy_avatar_storage_before_write
  on public.legacy_family_members;
create trigger everroot_legacy_avatar_storage_before_write
  before insert or update of avatar_path on public.legacy_family_members
  for each row
  execute function public.everroot_assert_legacy_avatar_storage_capacity();

drop trigger if exists everroot_highlight_photo_capacity_before_insert
  on public.vault_highlight_photos;
create trigger everroot_highlight_photo_capacity_before_insert
  before insert on public.vault_highlight_photos
  for each row
  execute function public.everroot_assert_photo_capacity();

do $$
begin
  if to_regclass('public.vault_about_photos') is not null then
    execute 'drop trigger if exists everroot_about_photo_capacity_before_insert on public.vault_about_photos';
    execute 'create trigger everroot_about_photo_capacity_before_insert
      before insert on public.vault_about_photos
      for each row
      execute function public.everroot_assert_photo_capacity()';
  end if;

  if to_regclass('public.memory_photos') is not null then
    execute 'drop trigger if exists everroot_memory_photo_capacity_before_insert on public.memory_photos';
    execute 'create trigger everroot_memory_photo_capacity_before_insert
      before insert on public.memory_photos
      for each row
      execute function public.everroot_assert_photo_capacity()';
  end if;

  if to_regclass('public.legacy_member_photos') is not null then
    execute 'drop trigger if exists everroot_legacy_member_photo_capacity_before_insert on public.legacy_member_photos';
    execute 'create trigger everroot_legacy_member_photo_capacity_before_insert
      before insert on public.legacy_member_photos
      for each row
      execute function public.everroot_assert_photo_capacity()';
  end if;

  if to_regclass('public.legacy_memory_photos') is not null then
    execute 'drop trigger if exists everroot_legacy_memory_photo_capacity_before_insert on public.legacy_memory_photos';
    execute 'create trigger everroot_legacy_memory_photo_capacity_before_insert
      before insert on public.legacy_memory_photos
      for each row
      execute function public.everroot_assert_photo_capacity()';
  end if;

  if to_regclass('public.legacy_vault_about_photos') is not null then
    execute 'drop trigger if exists everroot_legacy_about_photo_capacity_before_insert on public.legacy_vault_about_photos';
    execute 'create trigger everroot_legacy_about_photo_capacity_before_insert
      before insert on public.legacy_vault_about_photos
      for each row
      execute function public.everroot_assert_photo_capacity()';
  end if;

  if to_regclass('public.vault_core_voice_note') is not null then
    execute 'drop trigger if exists everroot_core_voice_capacity_before_insert on public.vault_core_voice_note';
    execute 'create trigger everroot_core_voice_capacity_before_insert
      before insert on public.vault_core_voice_note
      for each row
      execute function public.everroot_assert_voice_note_capacity()';
  end if;

  if to_regclass('public.memory_voice_notes') is not null then
    execute 'drop trigger if exists everroot_memory_voice_capacity_before_insert on public.memory_voice_notes';
    execute 'create trigger everroot_memory_voice_capacity_before_insert
      before insert on public.memory_voice_notes
      for each row
      execute function public.everroot_assert_voice_note_capacity()';
  end if;

  if to_regclass('public.legacy_memory_voice_notes') is not null then
    execute 'drop trigger if exists everroot_legacy_memory_voice_capacity_before_insert on public.legacy_memory_voice_notes';
    execute 'create trigger everroot_legacy_memory_voice_capacity_before_insert
      before insert on public.legacy_memory_voice_notes
      for each row
      execute function public.everroot_assert_voice_note_capacity()';
  end if;

  if to_regclass('public.legacy_vault_core_voice_note') is not null then
    execute 'drop trigger if exists everroot_legacy_core_voice_capacity_before_insert on public.legacy_vault_core_voice_note';
    execute 'create trigger everroot_legacy_core_voice_capacity_before_insert
      before insert on public.legacy_vault_core_voice_note
      for each row
      execute function public.everroot_assert_voice_note_capacity()';
  end if;
end
$$;

create or replace function public.everroot_period_start(p_at timestamptz default now())
returns date
language sql
stable
set search_path = public, pg_temp
as $$
  select date_trunc('month', p_at)::date;
$$;

create or replace function public.everroot_consume_ai_usage(
  p_family_id uuid default null,
  p_vault_id uuid default null,
  p_units integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_family_id uuid := p_family_id;
  v_plan text;
  v_scope_type text;
  v_scope_id uuid;
  v_limit integer;
  v_period date := public.everroot_period_start();
  v_used integer;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_units is null or p_units < 1 then
    p_units := 1;
  end if;

  if v_family_id is null and p_vault_id is not null then
    v_family_id := public.everroot_family_for_vault(p_vault_id);
  end if;

  v_plan := public.everroot_family_plan(v_family_id);

  if v_plan = 'everroot_family' and v_family_id is not null then
    if not exists (
      select 1
      from public.family_members fm
      where fm.family_id = v_family_id
        and fm.user_id = v_user_id
    ) then
      raise exception 'You are not a member of this EverRoot Family'
        using errcode = '42501';
    end if;

    v_scope_type := 'family';
    v_scope_id := v_family_id;
  else
    v_scope_type := 'user';
    v_scope_id := v_user_id;
  end if;

  perform pg_advisory_xact_lock(hashtext(v_scope_type || ':' || v_scope_id::text || ':ai:' || v_period::text));

  v_limit := public.everroot_limit_int(
    case when v_scope_type = 'family' then v_scope_id else null end,
    'ai_responses_monthly'
  );

  insert into public.everroot_ai_usage_periods (
    scope_type,
    scope_id,
    period_start,
    used_count
  ) values (
    v_scope_type,
    v_scope_id,
    v_period,
    0
  )
  on conflict (scope_type, scope_id, period_start) do nothing;

  select used_count
    into v_used
    from public.everroot_ai_usage_periods
   where scope_type = v_scope_type
     and scope_id = v_scope_id
     and period_start = v_period
   for update;

  if v_used + p_units > v_limit then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_AI_LIMIT',
      case v_scope_type
        when 'family' then 'This EverRoot Family has used this month''s AI allowance.'
        else 'You''ve used this month''s EverRoot Free AI allowance.'
      end
    );
  end if;

  update public.everroot_ai_usage_periods
     set used_count = used_count + p_units
   where scope_type = v_scope_type
     and scope_id = v_scope_id
     and period_start = v_period
   returning used_count into v_used;

  return jsonb_build_object(
    'scope_type', v_scope_type,
    'scope_id', v_scope_id,
    'period_start', v_period,
    'used', v_used,
    'limit', v_limit,
    'remaining', greatest(v_limit - v_used, 0)
  );
end;
$$;

revoke all on function public.everroot_consume_ai_usage(uuid, uuid, integer)
  from public;
grant execute on function public.everroot_consume_ai_usage(uuid, uuid, integer)
  to authenticated;

create or replace function public.join_family_by_relationship_invite(
  p_invite_code text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_invite public.family_invites%rowtype;
  v_vault_id uuid;
  v_primary_family_id uuid;
  v_make_primary boolean;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into v_invite
    from public.family_invites
   where upper(invite_code) = upper(btrim(p_invite_code))
     and expires_at > now()
   limit 1
   for update;

  if v_invite.id is null then
    raise exception 'Invite code is invalid or expired';
  end if;

  select id, family_id
    into v_vault_id, v_primary_family_id
    from public.vaults
   where owner_id = v_user_id
   limit 1
   for update;

  if v_vault_id is null then
    raise exception 'No vault found for this account';
  end if;

  if not exists (
    select 1
    from public.family_members fm
    where fm.family_id = v_invite.family_id
      and fm.user_id = v_user_id
  ) then
    perform public.everroot_assert_can_add_family_member(
      v_invite.family_id,
      v_user_id
    );
  end if;

  v_make_primary := v_primary_family_id is null;

  if v_make_primary then
    update public.family_members
       set is_primary = false
     where user_id = v_user_id;

    update public.vaults
       set family_id = v_invite.family_id
     where id = v_vault_id;
  end if;

  update public.family_members
     set role = case when role = 'owner' then role else 'member' end,
         slot_key = coalesce(slot_key, v_invite.slot_key),
         is_primary = case when v_make_primary then true else is_primary end
   where family_id = v_invite.family_id
     and user_id = v_user_id;

  if not found then
    insert into public.family_members (
      family_id,
      user_id,
      slot_key,
      role,
      joined_at,
      is_primary
    ) values (
      v_invite.family_id,
      v_user_id,
      v_invite.slot_key,
      'member',
      now(),
      v_make_primary
    );
  end if;

  update public.family_relationships
     set parent_type = 'vault',
         parent_id = v_vault_id
   where family_id = v_invite.family_id
     and parent_type = 'invite'
     and parent_id = v_invite.id;

  update public.family_relationships
     set child_type = 'vault',
         child_id = v_vault_id
   where family_id = v_invite.family_id
     and child_type = 'invite'
     and child_id = v_invite.id;

  delete from public.family_invites where id = v_invite.id;

  return v_invite.family_id;
end;
$$;

revoke all on function public.join_family_by_relationship_invite(text)
  from public;
grant execute on function public.join_family_by_relationship_invite(text)
  to authenticated;

create or replace function public.get_family_entitlements_and_usage(
  p_family_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_limits jsonb;
  v_personal_vault_id uuid;
  v_period date := public.everroot_period_start();
  v_ai_used integer := 0;
  v_invites_used integer := 0;
  v_real_members integer := 0;
  v_legacy_people integer := 0;
  v_storage_bytes bigint := 0;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_family_id is not null and not exists (
    select 1
    from public.family_members fm
    where fm.family_id = p_family_id
      and fm.user_id = v_user_id
  ) then
    raise exception 'You are not a member of this family'
      using errcode = '42501';
  end if;

  v_limits := public.everroot_limits(p_family_id);

  if p_family_id is null then
    select v.id
      into v_personal_vault_id
      from public.vaults v
     where v.owner_id = v_user_id
     order by v.created_at asc
     limit 1;
  end if;

  select coalesce(sum(used_count), 0)
    into v_ai_used
    from public.everroot_ai_usage_periods usage
   where usage.period_start = v_period
     and (
       (p_family_id is not null and usage.scope_type = 'family' and usage.scope_id = p_family_id)
       or (p_family_id is null and usage.scope_type = 'user' and usage.scope_id = v_user_id)
     );

  if p_family_id is not null then
    select count(*)
      into v_real_members
      from public.family_members fm
     where fm.family_id = p_family_id;

    select count(*)
      into v_legacy_people
      from public.legacy_family_members lfm
     where lfm.family_id = p_family_id
       and coalesce(lfm.replaced_by_vault_id::text, '') = '';

    select coalesce(sum(used_count), 0)
      into v_invites_used
      from public.everroot_invite_usage_periods usage
     where usage.family_id = p_family_id
       and usage.period_start = v_period;
  end if;

  v_storage_bytes := public.everroot_storage_bytes_used(
    p_family_id,
    v_personal_vault_id
  );

  return jsonb_build_object(
    'plan', v_limits->>'plan',
    'limits', v_limits,
    'usage', jsonb_build_object(
      'real_members', v_real_members,
      'legacy_people', v_legacy_people,
      'memories', public.everroot_memory_count(p_family_id, v_personal_vault_id),
      'photos', public.everroot_photo_count(p_family_id, v_personal_vault_id),
      'voice_notes', public.everroot_voice_note_count(p_family_id, v_personal_vault_id),
      'storage_bytes', v_storage_bytes,
      'ai_responses_monthly', v_ai_used,
      'invites_monthly', v_invites_used
    )
  );
end;
$$;

revoke all on function public.get_family_entitlements_and_usage(uuid)
  from public;
grant execute on function public.get_family_entitlements_and_usage(uuid)
  to authenticated;

grant select on table public.family_entitlements
  to authenticated;
grant select on table public.everroot_ai_usage_periods
  to authenticated;
grant select on table public.everroot_invite_usage_periods
  to authenticated;

revoke all on function public.everroot_touch_updated_at()
  from public, anon;
revoke all on function public.everroot_family_plan(uuid)
  from public, anon;
revoke all on function public.everroot_limits(uuid)
  from public, anon;
revoke all on function public.everroot_limit_int(uuid, text)
  from public, anon;
revoke all on function public.everroot_limit_bigint(uuid, text)
  from public, anon;
revoke all on function public.everroot_quota_error(text, text)
  from public, anon;
revoke all on function public.everroot_family_for_vault(uuid)
  from public, anon;
revoke all on function public.everroot_assert_can_add_family_member(uuid, uuid)
  from public, anon;
revoke all on function public.everroot_assert_family_member_capacity()
  from public, anon;
revoke all on function public.everroot_assert_invite_capacity()
  from public, anon;
revoke all on function public.everroot_assert_legacy_person_capacity()
  from public, anon;
revoke all on function public.everroot_memory_count(uuid, uuid)
  from public, anon;
revoke all on function public.everroot_assert_memory_capacity()
  from public, anon;
revoke all on function public.everroot_assert_legacy_memory_capacity()
  from public, anon;
revoke all on function public.everroot_photo_count(uuid, uuid)
  from public, anon;
revoke all on function public.everroot_voice_note_count(uuid, uuid)
  from public, anon;
revoke all on function public.everroot_family_id_from_legacy_member(uuid)
  from public, anon;
revoke all on function public.everroot_media_bucket_ids()
  from public, anon;
revoke all on function public.everroot_storage_metadata_size(jsonb)
  from public, anon;
revoke all on function public.everroot_try_uuid(text)
  from public, anon;
revoke all on function public.everroot_storage_bytes_used(uuid, uuid)
  from public, anon;
revoke all on function public.everroot_assert_storage_object_capacity()
  from public, anon;
revoke all on function public.everroot_assert_storage_capacity(uuid, uuid, text)
  from public, anon;
revoke all on function public.everroot_assert_photo_capacity()
  from public, anon;
revoke all on function public.everroot_assert_voice_note_capacity()
  from public, anon;
revoke all on function public.everroot_assert_vault_avatar_storage_capacity()
  from public, anon;
revoke all on function public.everroot_assert_legacy_avatar_storage_capacity()
  from public, anon;
revoke all on function public.everroot_period_start(timestamptz)
  from public, anon;
revoke all on function public.everroot_consume_ai_usage(uuid, uuid, integer)
  from public, anon;
revoke all on function public.get_family_entitlements_and_usage(uuid)
  from public, anon;

grant execute on function public.everroot_consume_ai_usage(uuid, uuid, integer)
  to authenticated;
grant execute on function public.get_family_entitlements_and_usage(uuid)
  to authenticated;
grant execute on function public.join_family_by_relationship_invite(text)
  to authenticated;
