-- EverRoot Life360-style entitlement adjustment.
--
-- Local-only fix-forward migration. This intentionally does not delete,
-- rewrite, or backfill any existing family, member, invite, vault, legacy,
-- memory, media, entitlement, or usage rows.
--
-- Product model change:
-- - free family invitations are growth, not monetization;
-- - media, storage, voice, AI, and large-family usage remain cost controls;
-- - a user still has only one primary/home family via the existing
--   family_members_one_primary_per_user partial unique index.
--
-- Production note:
-- A temporary TestFlight beta entitlement trigger is recorded in production as
-- 20260816101706 and 20260816101752. This migration does not create, drop, or
-- depend on that beta trigger. Decide whether the beta trigger should remain
-- active until its 2026-11-14 expiry before a public App Store launch.

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
      'invites_monthly', 25,
      'voice_seconds', 120
    )
  end;
$$;

revoke all on function public.everroot_limits(uuid) from public, anon, authenticated;
grant execute on function public.everroot_limits(uuid) to service_role;

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
          'This Ever Roots Family already has 20 real family accounts.'
        else
          'This Ever Roots Free family already has 8 real family accounts. You can still preserve more memories, but this family needs Ever Roots Family before another relative can join.'
      end
    );
  end if;
end;
$$;

revoke all on function public.everroot_assert_can_add_family_member(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.everroot_assert_can_add_family_member(uuid, uuid)
  to service_role;

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
      case v_plan
        when 'everroot_family' then
          'This Ever Roots Family has used this month''s invite allowance. Try again next month or contact support if you need help with a larger family.'
        else
          'This Ever Roots Free family has used this month''s invite allowance. Try again next month after your current relatives have joined.'
      end
    );
  end if;

  update public.everroot_invite_usage_periods
     set used_count = used_count + 1
   where family_id = new.family_id
     and period_start = v_period;

  return new;
end;
$$;

revoke all on function public.everroot_assert_invite_capacity()
  from public, anon, authenticated;
grant execute on function public.everroot_assert_invite_capacity()
  to service_role;

comment on function public.everroot_limits(uuid) is
  'EverRoot quota map. Free families may invite and grow to 8 real accounts; Ever Roots Family grows to 20. Expensive usage remains controlled by media, storage, voice, and AI quotas.';

comment on function public.everroot_assert_can_add_family_member(uuid, uuid) is
  'Server-side real-family-member quota guard. This no longer blocks non-primary free family joins; primary-family uniqueness remains enforced by family_members_one_primary_per_user.';

comment on function public.everroot_assert_invite_capacity() is
  'Server-side invite quota and cooldown guard. Free families can create invites, subject to monthly usage and anti-spam cooldown.';

do $$
declare
  v_beta_trigger_exists boolean;
  v_beta_function_exists boolean;
begin
  select exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'family_groups'
      and t.tgname = 'everroot_testflight_beta_family_entitlement_after_insert'
      and not t.tgisinternal
  ) into v_beta_trigger_exists;

  select to_regprocedure('public.everroot_grant_testflight_beta_entitlement()') is not null
    into v_beta_function_exists;

  raise notice
    'TestFlight beta entitlement reconciliation: trigger_exists=%, function_exists=%. Confirm beta migration history before production deployment.',
    v_beta_trigger_exists,
    v_beta_function_exists;
end
$$;
