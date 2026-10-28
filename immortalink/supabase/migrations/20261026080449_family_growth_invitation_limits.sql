-- Preserve every unrelated plan allowance from the deployed definition.
do $$
declare definition text; old_limit integer;
begin
  definition := pg_get_functiondef('public.everroot_limits(uuid)'::regprocedure);
  foreach old_limit in array array[8,20,30] loop
    if position('''real_members'', ' || old_limit in definition) = 0 then
      raise exception 'Unexpected member limits; inspect before applying';
    end if;
    definition := replace(definition, '''real_members'', ' || old_limit,
      '''real_members'', null::integer');
  end loop;
  foreach old_limit in array array[25,50,100] loop
    if position('''invites_monthly'', ' || old_limit in definition) = 0 then
      raise exception 'Unexpected invite limits; inspect before applying';
    end if;
    definition := replace(definition, '''invites_monthly'', ' || old_limit,
      '''invites_monthly'', null::integer, ''invites_hourly_per_member'', 20, ''invites_hourly_per_family'', 50');
  end loop;
  execute definition;
end;
$$;

create or replace function public.everroot_assert_invite_capacity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  stamp timestamptz;
  pending_cap integer;
  v_recipient_email text := nullif(lower(btrim(new.recipient_email)),'');
  v_recipient_phone text := nullif(regexp_replace(coalesce(new.recipient_phone,''),'\D','','g'),'');
begin
  if tg_op='UPDATE' then
    if new.id is distinct from old.id or new.family_id is distinct from old.family_id
        or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at
        or new.invite_code is distinct from old.invite_code
        or (old.used_at is not null and new.used_at is null)
        or (old.expires_at is not null and (new.expires_at is null or new.expires_at>old.expires_at)) then
      raise exception 'Create a new invite instead of reactivating or changing an old invite.' using errcode='42501';
    end if;
    return new;
  end if;
  if auth.uid() is not null and (new.created_by is distinct from auth.uid()
      or not exists(select 1 from public.family_members where family_id=new.family_id and user_id=auth.uid())) then
    raise exception 'Only a current family member can create an invite.' using errcode='42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('invite-actor:' || new.created_by::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(new.family_id::text || ':invites'));
  stamp := clock_timestamp();
  new.created_at := stamp;
  perform public.everroot_assert_family_writable(new.family_id);
  perform family_access.assert_growth_storage(new.family_id);

  delete from family_access.invite_rate_events
    where created_at<=stamp-interval '1 hour' and (family_id=new.family_id or actor_id=new.created_by);
  if exists(select 1 from family_access.invite_rate_events where family_id=new.family_id
      and actor_id=new.created_by and created_at>stamp-interval '10 seconds') then
    perform public.everroot_quota_error('ERR_EVERROOT_INVITE_COOLDOWN','Please wait a moment before creating another invite.');
  end if;
  if (select count(*) from family_access.invite_rate_events where actor_id=new.created_by and created_at>stamp-interval '1 hour')
      >=public.everroot_limit_int(new.family_id,'invites_hourly_per_member')
      or (select count(*) from family_access.invite_rate_events where family_id=new.family_id and created_at>stamp-interval '1 hour')
      >=public.everroot_limit_int(new.family_id,'invites_hourly_per_family') then
    perform public.everroot_quota_error('ERR_EVERROOT_INVITE_RATE_LIMIT',
      'Too many invites were created in the last hour. Please wait before creating another invite.');
  end if;
  pending_cap := public.everroot_limit_int(new.family_id,'pending_invites');
  if (select count(*) from public.family_invites where family_id=new.family_id and used_at is null
      and (expires_at is null or expires_at>stamp))>=pending_cap then
    perform public.everroot_quota_error('ERR_EVERROOT_PENDING_INVITE_LIMIT',
      'This family already has too many active invite codes. Wait for relatives to join or let older invites expire.');
  end if;
  if v_recipient_email is not null and exists(select 1 from public.family_invites fi
      where fi.family_id=new.family_id and fi.used_at is null and (fi.expires_at is null or fi.expires_at>stamp)
        and lower(btrim(fi.recipient_email))=v_recipient_email) then
    perform public.everroot_quota_error('ERR_EVERROOT_DUPLICATE_INVITE_RECIPIENT','This family already has an active invite for that email.');
  end if;
  if v_recipient_phone is not null and exists(select 1 from public.family_invites fi
      where fi.family_id=new.family_id and fi.used_at is null and (fi.expires_at is null or fi.expires_at>stamp)
        and nullif(regexp_replace(coalesce(fi.recipient_phone,''),'\D','','g'),'')=v_recipient_phone) then
    perform public.everroot_quota_error('ERR_EVERROOT_DUPLICATE_INVITE_RECIPIENT','This family already has an active invite for that phone number.');
  end if;
  insert into family_access.invite_rate_events(invite_id,family_id,actor_id,created_at)
    values(new.id,new.family_id,new.created_by,stamp);
  -- Retain monthly usage statistics, but no monthly growth paywall.
  insert into public.everroot_invite_usage_periods(family_id,period_start,used_count)
    values(new.family_id,date_trunc('month',stamp)::date,1)
    on conflict(family_id,period_start) do update
      set used_count=public.everroot_invite_usage_periods.used_count+1;
  return new;
end;
$$;
drop trigger everroot_invite_capacity_before_insert on public.family_invites;
create trigger everroot_invite_capacity_before_insert
before insert or update on public.family_invites
for each row execute function public.everroot_assert_invite_capacity();

comment on function public.everroot_limits(uuid) is
  'Family allowances: null real_members and invites_monthly mean no total/monthly cap; rolling hourly, pending, legacy-profile and storage safeguards remain.';
