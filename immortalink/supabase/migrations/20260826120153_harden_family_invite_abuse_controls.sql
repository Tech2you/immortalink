-- Harden family invite abuse controls without changing the invite UX.
--
-- This keeps family growth free and code-based, but prevents a family from
-- accumulating too many active unused invite codes at once. Recipient fields are
-- nullable so existing Flutter clients can continue creating invites exactly as
-- they do today.

alter table public.family_invites
  add column if not exists recipient_email text,
  add column if not exists recipient_phone text;

comment on column public.family_invites.recipient_email is
  'Optional invite recipient email. Used for duplicate-pending invite prevention when supplied by clients.';

comment on column public.family_invites.recipient_phone is
  'Optional invite recipient phone. Used for duplicate-pending invite prevention when supplied by clients.';

create index if not exists family_invites_pending_email_lookup_idx
  on public.family_invites (family_id, lower(btrim(recipient_email)))
  where used_at is null
    and recipient_email is not null
    and btrim(recipient_email) <> '';

create index if not exists family_invites_pending_phone_lookup_idx
  on public.family_invites (
    family_id,
    nullif(regexp_replace(coalesce(recipient_phone, ''), '\D', '', 'g'), '')
  )
  where used_at is null
    and recipient_phone is not null
    and btrim(recipient_phone) <> '';

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
      'pending_invites', 25,
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
      'pending_invites', 10,
      'voice_seconds', 120
    )
  end;
$$;

revoke all on function public.everroot_limits(uuid) from public, anon, authenticated;
grant execute on function public.everroot_limits(uuid) to service_role;

create or replace function public.everroot_assert_invite_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_plan text;
  v_monthly_limit integer;
  v_monthly_used integer;
  v_pending_limit integer;
  v_pending_used integer;
  v_recipient_email text := nullif(lower(btrim(new.recipient_email)), '');
  v_recipient_phone text := nullif(regexp_replace(coalesce(new.recipient_phone, ''), '\D', '', 'g'), '');
  v_period date := date_trunc('month', now())::date;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext(new.family_id::text || ':invites'));

  v_plan := public.everroot_family_plan(new.family_id);
  v_monthly_limit := public.everroot_limit_int(new.family_id, 'invites_monthly');
  v_pending_limit := public.everroot_limit_int(new.family_id, 'pending_invites');

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

  select count(*)
    into v_pending_used
    from public.family_invites fi
   where fi.family_id = new.family_id
     and fi.used_at is null
     and (
       fi.expires_at is null
       or fi.expires_at > now()
     );

  if coalesce(v_pending_used, 0) >= coalesce(v_pending_limit, v_monthly_limit) then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_PENDING_INVITE_LIMIT',
      case v_plan
        when 'everroot_family' then
          'This Ever Roots Family already has too many active invite codes. Wait for relatives to join, let older invites expire, or contact support if you need help with a larger family.'
        else
          'This Ever Roots Free family already has too many active invite codes. Wait for relatives to join or let older invites expire before creating more.'
      end
    );
  end if;

  if v_recipient_email is not null and exists (
    select 1
    from public.family_invites fi
    where fi.family_id = new.family_id
      and fi.used_at is null
      and (
        fi.expires_at is null
        or fi.expires_at > now()
      )
      and lower(btrim(fi.recipient_email)) = v_recipient_email
  ) then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_DUPLICATE_INVITE_RECIPIENT',
      'This family already has an active invite for that email.'
    );
  end if;

  if v_recipient_phone is not null and exists (
    select 1
    from public.family_invites fi
    where fi.family_id = new.family_id
      and fi.used_at is null
      and (
        fi.expires_at is null
        or fi.expires_at > now()
      )
      and nullif(regexp_replace(coalesce(fi.recipient_phone, ''), '\D', '', 'g'), '') = v_recipient_phone
  ) then
    perform public.everroot_quota_error(
      'ERR_EVERROOT_DUPLICATE_INVITE_RECIPIENT',
      'This family already has an active invite for that phone number.'
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
    into v_monthly_used
    from public.everroot_invite_usage_periods
   where family_id = new.family_id
     and period_start = v_period
   for update;

  if coalesce(v_monthly_used, 0) >= v_monthly_limit then
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

comment on function public.everroot_assert_invite_capacity() is
  'Server-side invite quota, pending-active-invite, duplicate-recipient, and cooldown guard.';

revoke all on table public.family_invites from anon;
revoke delete, truncate, trigger, references on table public.family_invites
  from authenticated;
grant select, insert, update on table public.family_invites to authenticated;
