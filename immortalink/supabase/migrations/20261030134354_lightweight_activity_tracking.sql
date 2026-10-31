-- Analytics is an independent best-effort RPC. No triggers or changes on app,
-- billing, invitation, relationship, memory, storage or auth business tables.
create schema heiro_activity;
revoke all on schema heiro_activity from public, anon, authenticated, service_role;
grant usage on schema heiro_activity to authenticated;

create table heiro_activity.settings (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default true,
  -- Remains false until the Apple privacy declaration covers product analytics.
  production_enabled boolean not null default false,
  enabled_at timestamptz not null default now(),
  production_started_at timestamptz,
  check(not production_enabled or production_started_at is not null)
);
insert into heiro_activity.settings(singleton) values(true);
create table heiro_activity.daily (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  test_build boolean not null,
  primary key(user_id,day,test_build)
);
create index activity_daily_day_idx on heiro_activity.daily(day,user_id);
create table heiro_activity.milestones (
  user_id uuid not null references auth.users(id) on delete cascade,
  test_build boolean not null,
  first_memory_saved_on date,
  first_invite_accepted_on date,
  primary key(user_id,test_build)
);
alter table heiro_activity.settings enable row level security;
alter table heiro_activity.daily enable row level security;
alter table heiro_activity.milestones enable row level security;
revoke all on all tables in schema heiro_activity from public,anon,authenticated,service_role;

create function heiro_activity.record(
  p_expected_user_id uuid, p_event text, p_subject_id uuid, p_test_build boolean
) returns boolean language plpgsql security definer set search_path='' set statement_timeout='2s' as $$
declare v_uid uuid:=auth.uid(); v_day date:=(now() at time zone 'UTC')::date; v_settings heiro_activity.settings;
begin
  if v_uid is null or p_expected_user_id is distinct from v_uid or not exists(
    select 1 from auth.users where id=v_uid and deleted_at is null and not coalesce(is_anonymous,false)
      and (banned_until is null or banned_until<now())
  ) or not exists(
    select 1 from auth.sessions where user_id=v_uid and id::text=auth.jwt()->>'session_id'
      and (not_after is null or not_after>now())
  ) then raise exception 'ACTIVITY_ACCESS_DENIED' using errcode='42501'; end if;
  if p_event is null or p_event not in ('active','memory_saved','invite_accepted') or p_test_build is null
    then raise exception 'INVALID_ACTIVITY'; end if;
  select * into v_settings from heiro_activity.settings where singleton;
  if not v_settings.enabled or (not p_test_build and not v_settings.production_enabled) then return false; end if;
  -- Avoid storing analytics for explicitly excluded test accounts in production.
  if not p_test_build and exists(select 1 from heiro_business.exclusions where kind='account' and subject_id=v_uid)
    then return true; end if;
  if p_event='active' and p_subject_id is not null then raise exception 'INVALID_ACTIVITY'; end if;
  if p_event='memory_saved' and not exists(
    select 1 from public.memories m join public.vaults v on v.id=m.vault_id
    where m.id=p_subject_id and v.owner_id=v_uid and coalesce(m.prompt_key,'')<>'about_me'
      and m.created_at>=now()-interval '24 hours'
  ) then raise exception 'INVALID_ACTIVITY_SUBJECT'; end if;
  if p_event='invite_accepted' and not exists(
    -- Relationship invite redemption intentionally deletes its invite row.
    -- Confirm the successful join via recent membership, not a retained code.
    select 1 from public.family_members fm where fm.family_id=p_subject_id
      and fm.user_id=v_uid and fm.joined_at>=now()-interval '24 hours'
  ) then raise exception 'INVALID_ACTIVITY_SUBJECT'; end if;
  -- The database supplies UTC dates and makes duplicate requests no-ops.
  insert into heiro_activity.daily values(v_uid,v_day,p_test_build) on conflict do nothing;
  if p_event='memory_saved' then
    insert into heiro_activity.milestones(user_id,test_build,first_memory_saved_on) values(v_uid,p_test_build,v_day)
    on conflict(user_id,test_build) do update set first_memory_saved_on=excluded.first_memory_saved_on
    where heiro_activity.milestones.first_memory_saved_on is null;
  elsif p_event='invite_accepted' then
    insert into heiro_activity.milestones(user_id,test_build,first_invite_accepted_on) values(v_uid,p_test_build,v_day)
    on conflict(user_id,test_build) do update set first_invite_accepted_on=excluded.first_invite_accepted_on
    where heiro_activity.milestones.first_invite_accepted_on is null;
  end if;
  return true;
end; $$;

create function public.record_app_activity(
  p_expected_user_id uuid, p_event text, p_subject_id uuid default null, p_test_build boolean default false
) returns boolean language sql security invoker set search_path='' as $$
  select heiro_activity.record(p_expected_user_id,p_event,p_subject_id,p_test_build);
$$;

create function heiro_activity.metrics() returns jsonb
language sql stable security definer set search_path='' as $$
with eligible as (
  select u.id from auth.users u where u.deleted_at is null and not coalesce(u.is_anonymous,false)
    and not exists(select 1 from heiro_business.exclusions x where x.kind='account' and x.subject_id=u.id)
    -- An excluded test family's activity is excluded too, unless this account
    -- also belongs to a nonexcluded family. Family-less accounts remain eligible.
    and (not exists(select 1 from public.family_members fm where fm.user_id=u.id)
      or exists(select 1 from public.family_members fm where fm.user_id=u.id and not exists(
        select 1 from heiro_business.exclusions x where x.kind='family' and x.subject_id=fm.family_id)))
), days as (
  select d.* from heiro_activity.daily d join eligible e on e.id=d.user_id
  where not d.test_build and d.day between (now() at time zone 'UTC')::date-29 and (now() at time zone 'UTC')::date
), milestones as (
  select m.* from heiro_activity.milestones m join eligible e on e.id=m.user_id where not m.test_build
)
select jsonb_build_object(
  'activity_status',case when not s.enabled then 'paused' when not s.production_enabled then 'testing_only' else 'collecting' end,
  'activity_enabled',s.enabled,
  'activity_started_at',s.production_started_at,
  'monthly_active_users',case when s.production_started_at is not null then (select count(distinct user_id) from days) end,
  'daily_active_users',case when s.production_started_at is not null then (select count(*) from days where day=(now() at time zone 'UTC')::date) end,
  'returning_active_users_30d',case when s.production_started_at is not null then (select count(*) from (select user_id from days group by user_id having count(*)>=2) x) end,
  'first_observed_saves_30d',case when s.production_started_at is not null then (select count(*) from milestones where first_memory_saved_on>=(now() at time zone 'UTC')::date-29) end,
  'first_observed_invites_30d',case when s.production_started_at is not null then (select count(*) from milestones where first_invite_accepted_on>=(now() at time zone 'UTC')::date-29) end,
  'test_active_today',(select count(*) from heiro_activity.daily where test_build and day=(now() at time zone 'UTC')::date),
  'test_saves_observed',(select count(*) from heiro_activity.milestones where test_build and first_memory_saved_on is not null),
  'test_invites_observed',(select count(*) from heiro_activity.milestones where test_build and first_invite_accepted_on is not null)
) from heiro_activity.settings s where singleton;
$$;

create function heiro_activity.set_enabled(p_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
declare v_uid uuid;
begin
  v_uid:=heiro_business.require_owner();
  if p_enabled is null then raise exception 'INVALID_ACTIVITY_SETTING'; end if;
  update heiro_activity.settings set enabled=p_enabled where singleton;
  insert into heiro_business.audit(actor_id,action,target) values(v_uid,'activity_collection',p_enabled::text);
end; $$;
create function public.business_set_activity_enabled(p_enabled boolean) returns void
language sql security invoker set search_path='' as $$select heiro_activity.set_enabled(p_enabled);$$;

create function heiro_activity.prune() returns void
language sql security definer set search_path='' as $$
  delete from heiro_activity.daily where day<=(now() at time zone 'UTC')::date-90;
$$;

revoke all on all functions in schema heiro_activity from public,anon,authenticated,service_role;
revoke all on function public.record_app_activity(uuid,text,uuid,boolean) from public,anon,service_role;
revoke all on function public.business_set_activity_enabled(boolean) from public,anon,service_role;
grant execute on function heiro_activity.record(uuid,text,uuid,boolean),heiro_activity.set_enabled(boolean) to authenticated;
grant execute on function public.record_app_activity(uuid,text,uuid,boolean),public.business_set_activity_enabled(boolean) to authenticated;

-- Deployment hosts with pg_cron prune daily. The local SQL test runtime need not
-- install an extension or alter any existing app/snapshot job.
do $$begin
  if exists(select 1 from pg_namespace where nspname='cron') then
    perform cron.schedule('heiro-activity-retention','15 0 * * *','select heiro_activity.prune()');
  end if;
end;$$;

-- Preserve every existing paid-account and cost calculation; append activity.
create or replace function heiro_business.collect_metrics() returns jsonb
language sql stable security definer set search_path = '' as $$
with eligible_users as (
  select id,created_at from auth.users u where deleted_at is null and not coalesce(is_anonymous,false)
    and not exists(select 1 from heiro_business.exclusions x where x.kind='account' and x.subject_id=u.id)
), eligible_families as (
  select g.id from public.family_groups g where
    not exists(select 1 from heiro_business.exclusions x where x.kind='family' and x.subject_id=g.id)
    and exists(select 1 from public.family_members fm join eligible_users u on u.id=fm.user_id where fm.family_id=g.id)
), plans as (
  select e.*,event.raw_payload->>'price' as verified_price,
    event.raw_payload->>'offerDiscountType' as discount_type
  from public.family_entitlements e
  join eligible_families f on f.id=e.family_id
  join eligible_users u on u.id=e.billing_owner_user_id
  left join lateral (
    select raw_payload from public.apple_subscription_events ev
    where ev.apple_environment='production' and ev.apple_original_transaction_id=e.apple_original_transaction_id
      and ev.family_id=e.family_id and ev.entitlement_status='active'
    order by ev.created_at desc,ev.id desc limit 1
  ) event on true
  where e.apple_environment='production' and e.plan in ('everroot_family','everroot_legacy')
    and e.status='active' and e.current_period_end>now() and e.apple_original_transaction_id is not null
), paid as (
  select * from plans where case when verified_price ~ '^[0-9]+$' then verified_price::numeric>0 else false end
    and coalesce(discount_type,'')<>'FREE_TRIAL'
), file_sizes as (
  select case when metadata->>'size' ~ '^[0-9]+$' then (metadata->>'size')::numeric else 0 end as bytes
  from storage.objects
)
select jsonb_build_object(
  'accounts',(select count(*) from eligible_users),
  'families',(select count(*) from eligible_families),
  'paying_contributors',(select count(distinct billing_owner_user_id) from paid),
  'funded_families',(select count(distinct family_id) from paid),
  'active_production_plans',(select count(*) from plans),
  'unclassified_plans',(select count(*) from plans where verified_price is null or verified_price !~ '^[0-9]+$'),
  'free_offer_plans',(select count(*) from plans where case when verified_price ~ '^[0-9]+$' then verified_price::numeric=0 else false end),
  'storage_bytes',(select coalesce(sum(bytes),0) from file_sizes),
  'storage_objects',(select count(*) from file_sizes),
  'excluded_accounts',(select count(*) from heiro_business.exclusions where kind='account'),
  'excluded_families',(select count(*) from heiro_business.exclusions where kind='family'),
  'new_accounts_30d',(select count(*) from eligible_users where created_at>=now()-interval '30 days'),
  'monthly_active_users',null,
  'activity_status','not_instrumented',
  'paid_basis','production_verified_positive_price',
  'storage_basis','all_objects_including_testing',
  'observed_at',now()
) || heiro_activity.metrics(); $$;

