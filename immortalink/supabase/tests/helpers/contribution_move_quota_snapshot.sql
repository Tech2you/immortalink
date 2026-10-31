-- Existing quota consumers captured read-only on 2026-10-30, before moves.
CREATE OR REPLACE FUNCTION public.everroot_consume_ai_usage(p_family_id uuid DEFAULT NULL::uuid, p_vault_id uuid DEFAULT NULL::uuid, p_units integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  perform public.everroot_assert_family_writable(v_family_id);
  perform public.everroot_assert_usage_burst('ai',p_units);
  v_plan := public.everroot_family_plan(v_family_id);

  if v_plan in ('everroot_family', 'everroot_legacy') and v_family_id is not null then
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
$function$
;

CREATE OR REPLACE FUNCTION public.everroot_consume_transcription_usage(p_family_id uuid DEFAULT NULL::uuid, p_vault_id uuid DEFAULT NULL::uuid, p_seconds integer DEFAULT 120)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  -- Use the full duration supplied by the transcription service.

  if v_family_id is null and p_vault_id is not null then
    v_family_id := public.everroot_family_for_vault(p_vault_id);
  end if;

  perform public.everroot_assert_family_writable(v_family_id);
  perform public.everroot_assert_usage_burst('transcription',1);
  v_plan := public.everroot_family_plan(v_family_id);

  if v_plan in ('everroot_family', 'everroot_legacy') and v_family_id is not null then
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
$function$
;

