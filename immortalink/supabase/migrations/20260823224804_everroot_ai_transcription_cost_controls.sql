-- EverRoot AI and transcription cost controls.
--
-- Fix-forward migration. This separates paid OpenAI transcription usage from
-- general AI chat/icebreaker usage so a family can exhaust one allowance
-- without silently consuming the other. It does not delete, rewrite, or
-- backfill existing family, vault, memory, media, or AI usage rows.

alter table if exists public.memory_voice_notes
  add column if not exists duration_seconds integer;

alter table if exists public.legacy_memory_voice_notes
  add column if not exists duration_seconds integer;

do $$
begin
  if to_regclass('public.memory_voice_notes') is not null
     and not exists (
       select 1
       from pg_constraint
       where conname = 'memory_voice_notes_duration_seconds_check'
         and conrelid = 'public.memory_voice_notes'::regclass
     ) then
    alter table public.memory_voice_notes
      add constraint memory_voice_notes_duration_seconds_check
      check (duration_seconds is null or duration_seconds between 1 and 120);
  end if;

  if to_regclass('public.legacy_memory_voice_notes') is not null
     and not exists (
       select 1
       from pg_constraint
       where conname = 'legacy_memory_voice_notes_duration_seconds_check'
         and conrelid = 'public.legacy_memory_voice_notes'::regclass
     ) then
    alter table public.legacy_memory_voice_notes
      add constraint legacy_memory_voice_notes_duration_seconds_check
      check (duration_seconds is null or duration_seconds between 1 and 120);
  end if;
end
$$;

create table if not exists public.everroot_transcription_usage_periods (
  id uuid primary key default gen_random_uuid(),
  scope_type text not null,
  scope_id uuid not null,
  period_start date not null,
  used_seconds integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint everroot_transcription_usage_scope_type_check
    check (scope_type in ('user', 'family')),
  constraint everroot_transcription_usage_used_seconds_check
    check (used_seconds >= 0)
);

create unique index if not exists everroot_transcription_usage_scope_period_unique
  on public.everroot_transcription_usage_periods(scope_type, scope_id, period_start);

alter table public.everroot_transcription_usage_periods enable row level security;

drop policy if exists "users can view their own everroot transcription usage"
  on public.everroot_transcription_usage_periods;
create policy "users can view their own everroot transcription usage"
  on public.everroot_transcription_usage_periods
  for select
  to authenticated
  using (
    (scope_type = 'user' and scope_id = (select auth.uid()))
    or (
      scope_type = 'family'
      and exists (
        select 1
        from public.family_members fm
        where fm.family_id = everroot_transcription_usage_periods.scope_id
          and fm.user_id = (select auth.uid())
      )
    )
  );

drop trigger if exists everroot_transcription_usage_periods_touch_updated_at
  on public.everroot_transcription_usage_periods;
create trigger everroot_transcription_usage_periods_touch_updated_at
  before update on public.everroot_transcription_usage_periods
  for each row
  execute function public.everroot_touch_updated_at();

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
      'real_members', 20,
      'legacy_people', 100,
      'memories', 1000,
      'photos', 2000,
      'voice_notes', 500,
      'storage_bytes', 10737418240,
      'ai_responses_monthly', 500,
      'transcription_seconds_monthly', 36000,
      'invites_monthly', 50,
      'voice_seconds', 120
    )
    else jsonb_build_object(
      'plan', 'free',
      'real_members', 8,
      'legacy_people', 8,
      'memories', 100,
      'photos', 100,
      'voice_notes', 25,
      'storage_bytes', 524288000,
      'ai_responses_monthly', 20,
      'transcription_seconds_monthly', 600,
      'invites_monthly', 25,
      'voice_seconds', 120
    )
  end;
$$;

revoke all on function public.everroot_limits(uuid) from public, anon, authenticated;
grant execute on function public.everroot_limits(uuid) to service_role;

create or replace function public.everroot_consume_transcription_usage(
  p_family_id uuid default null,
  p_vault_id uuid default null,
  p_seconds integer default 120
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
  v_seconds integer := coalesce(p_seconds, 120);
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if v_seconds < 1 then
    v_seconds := 120;
  end if;

  -- Current voice-note UX/server policy caps a single note at 120 seconds.
  -- Do not trust clients to report a larger/smaller value as the billing
  -- boundary until the DB stores verified audio duration.
  v_seconds := least(v_seconds, 120);

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

  perform pg_advisory_xact_lock(
    hashtext(v_scope_type || ':' || v_scope_id::text || ':transcription:' || v_period::text)
  );

  v_limit := public.everroot_limit_int(
    case when v_scope_type = 'family' then v_scope_id else null end,
    'transcription_seconds_monthly'
  );

  insert into public.everroot_transcription_usage_periods (
    scope_type,
    scope_id,
    period_start,
    used_seconds
  ) values (
    v_scope_type,
    v_scope_id,
    v_period,
    0
  )
  on conflict (scope_type, scope_id, period_start) do nothing;

  select used_seconds
    into v_used
    from public.everroot_transcription_usage_periods
   where scope_type = v_scope_type
     and scope_id = v_scope_id
     and period_start = v_period
   for update;

  if v_used + v_seconds > v_limit then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_TRANSCRIPTION_LIMIT',
      case v_scope_type
        when 'family' then 'This EverRoot Family has used this month''s voice transcription allowance.'
        else 'You''ve used this month''s EverRoot Free voice transcription allowance.'
      end
    );
  end if;

  update public.everroot_transcription_usage_periods
     set used_seconds = used_seconds + v_seconds
   where scope_type = v_scope_type
     and scope_id = v_scope_id
     and period_start = v_period
   returning used_seconds into v_used;

  return jsonb_build_object(
    'scope_type', v_scope_type,
    'scope_id', v_scope_id,
    'period_start', v_period,
    'used_seconds', v_used,
    'limit_seconds', v_limit,
    'remaining_seconds', greatest(v_limit - v_used, 0)
  );
end;
$$;

revoke all on function public.everroot_consume_transcription_usage(uuid, uuid, integer)
  from public, anon;
grant execute on function public.everroot_consume_transcription_usage(uuid, uuid, integer)
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
  v_transcription_used integer := 0;
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

  select coalesce(sum(used_seconds), 0)
    into v_transcription_used
    from public.everroot_transcription_usage_periods usage
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
      'transcription_seconds_monthly', v_transcription_used,
      'invites_monthly', v_invites_used
    )
  );
end;
$$;

revoke all on function public.get_family_entitlements_and_usage(uuid)
  from public, anon;
grant execute on function public.get_family_entitlements_and_usage(uuid)
  to authenticated;

grant select on table public.everroot_transcription_usage_periods
  to authenticated;

comment on table public.everroot_transcription_usage_periods is
  'Monthly EverRoot transcription usage by user or paid family. Separate from chat/icebreaker AI response usage.';

comment on function public.everroot_consume_transcription_usage(uuid, uuid, integer) is
  'Server-side monthly transcription allowance guard. Uses verified auth membership and caps per-call usage at the current 120-second voice-note ceiling.';
