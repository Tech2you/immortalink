-- Isolated owner reporting. No changes to app tables, billing, media or auth policies.
create schema if not exists heiro_business;
revoke all on schema heiro_business from public, anon, authenticated;
grant usage on schema heiro_business to authenticated;

create table heiro_business.owners (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table heiro_business.exclusions (
  kind text not null check (kind in ('account','family')),
  subject_id uuid not null,
  reason text not null check (length(reason) between 1 and 160),
  created_at timestamptz not null default now(),
  primary key(kind,subject_id)
);
create table heiro_business.snapshots (
  day date primary key,
  captured_at timestamptz not null,
  metrics jsonb not null
);
create table heiro_business.entries (
  id uuid primary key,
  month date not null check (extract(day from month)=1),
  kind text not null check (kind in ('expense','apple_proceeds','bank_payment')),
  category text not null check (category in ('Supabase','OpenAI','Resend','Hosting','Apple','Development','Marketing','Other')),
  reference text not null check (length(reference) between 1 and 160),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  amount numeric(16,2) not null check (amount between -1000000000 and 1000000000),
  zar_rate numeric(16,6) not null check (zar_rate > 0 and zar_rate <= 1000000),
  period_start date,
  period_end date,
  source_hash text check (source_hash is null or source_hash ~ '^[a-f0-9]{64}$'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (currency <> 'ZAR' or zar_rate=1),
  check ((period_start is null and period_end is null) or (period_start is not null and period_end >= period_start))
);
create unique index business_entries_source_unique on heiro_business.entries(source_hash,currency) where source_hash is not null;
create index business_entries_month_idx on heiro_business.entries(month);
create table heiro_business.monthly_reports (
  month date primary key check (extract(day from month)=1),
  mrr_zar numeric(16,2) check (mrr_zar between 0 and 1000000000),
  starting_payers integer check (starting_payers between 0 and 100000000),
  lost_starting_payers integer check (lost_starting_payers between 0 and starting_payers),
  reference text not null check (length(reference) between 1 and 160),
  costs_complete boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  check ((starting_payers is null and lost_starting_payers is null) or
         (starting_payers is not null and lost_starting_payers is not null))
);
create table heiro_business.audit (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  target text,
  created_at timestamptz not null default now()
);
alter table heiro_business.owners enable row level security;
alter table heiro_business.exclusions enable row level security;
alter table heiro_business.snapshots enable row level security;
alter table heiro_business.entries enable row level security;
alter table heiro_business.monthly_reports enable row level security;
alter table heiro_business.audit enable row level security;
revoke all on all tables in schema heiro_business from public,anon,authenticated,service_role;
revoke all on all sequences in schema heiro_business from public,anon,authenticated,service_role;

create function heiro_business.require_owner() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_session text := auth.jwt()->>'session_id';
begin
  if v_uid is null or not exists(select 1 from heiro_business.owners where user_id=v_uid)
    or not exists(select 1 from auth.users where id=v_uid and deleted_at is null
      and not coalesce(is_anonymous,false) and (banned_until is null or banned_until<now()))
    or not exists(select 1 from auth.sessions where id::text=v_session and user_id=v_uid
      and (not_after is null or not_after>now())) then
    raise exception 'BUSINESS_ACCESS_DENIED' using errcode='42501';
  end if;
  -- Respect an already-enrolled authenticator rather than bypassing it here.
  if exists(select 1 from auth.mfa_factors where user_id=v_uid and status='verified')
    and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
    raise exception 'BUSINESS_MFA_REQUIRED' using errcode='42501';
  end if;
  return v_uid;
end; $$;

create function heiro_business.collect_metrics() returns jsonb
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
); $$;

-- Only the database scheduler/postgres may call this; no client grant.
create function heiro_business.capture_daily() returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into heiro_business.snapshots(day,captured_at,metrics)
  values((now() at time zone 'UTC')::date,now(),heiro_business.collect_metrics())
  on conflict(day) do update set captured_at=excluded.captured_at,metrics=excluded.metrics;
end; $$;

create function heiro_business.dashboard(p_month date) returns jsonb
language plpgsql security definer set search_path = '' set statement_timeout='10s' as $$
declare v_uid uuid; v_metrics jsonb; v_report jsonb; v_entries jsonb; v_history jsonb;
begin
  v_uid:=heiro_business.require_owner();
  if p_month is null or extract(day from p_month)<>1 or p_month<date '2025-01-01'
    or p_month>(date_trunc('month',now())+interval '1 month')::date then raise exception 'INVALID_MONTH'; end if;
  v_metrics:=heiro_business.collect_metrics();
  select to_jsonb(r)-'updated_by' into v_report from heiro_business.monthly_reports r where month=p_month;
  select coalesce(jsonb_agg(to_jsonb(e)-'created_by' order by e.created_at desc),'[]'::jsonb)
    into v_entries from heiro_business.entries e where month=p_month;
  select coalesce(jsonb_agg(jsonb_build_object('day',day,'captured_at',captured_at,'metrics',metrics) order by day),'[]'::jsonb)
    into v_history from heiro_business.snapshots where day>=(now() at time zone 'UTC')::date-90;
  return jsonb_build_object('current',v_metrics,'month',p_month,'report',v_report,'entries',v_entries,'history',v_history,
    'exclusions',(select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'subject_id',subject_id,'reason',reason)),'[]'::jsonb) from heiro_business.exclusions));
end; $$;

create function heiro_business.write_entry(p_entry jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=heiro_business.require_owner(); v_id uuid:=(p_entry->>'id')::uuid;
begin
  if pg_column_size(p_entry)>8192 or v_id is null then raise exception 'INVALID_ENTRY'; end if;
  if exists(select 1 from heiro_business.entries where id=v_id) then
    -- Network retries are idempotent; changed content must use a new entry.
    if exists(select 1 from heiro_business.entries e where e.id=v_id and
      e.month=(p_entry->>'month')::date and e.kind=p_entry->>'kind' and e.category=p_entry->>'category'
      and e.reference=p_entry->>'reference' and e.amount=(p_entry->>'amount')::numeric
      and e.currency=p_entry->>'currency' and e.zar_rate=(p_entry->>'zar_rate')::numeric
      and e.source_hash is not distinct from nullif(p_entry->>'source_hash','')
      and e.period_start is not distinct from nullif(p_entry->>'period_start','')::date
      and e.period_end is not distinct from nullif(p_entry->>'period_end','')::date) then return v_id;
    end if;
    raise exception 'ENTRY_ID_ALREADY_USED';
  end if;
  if (p_entry->>'month')::date<date '2025-01-01' or
    (p_entry->>'month')::date>(date_trunc('month',now())+interval '1 month')::date then raise exception 'INVALID_MONTH'; end if;
  insert into heiro_business.entries(id,month,kind,category,reference,currency,amount,zar_rate,period_start,period_end,source_hash,created_by)
  values(v_id,(p_entry->>'month')::date,p_entry->>'kind',p_entry->>'category',p_entry->>'reference',
    p_entry->>'currency',(p_entry->>'amount')::numeric,(p_entry->>'zar_rate')::numeric,
    nullif(p_entry->>'period_start','')::date,nullif(p_entry->>'period_end','')::date,nullif(p_entry->>'source_hash',''),v_uid);
  update heiro_business.monthly_reports set costs_complete=false,updated_at=now(),updated_by=v_uid
    where month=(p_entry->>'month')::date and p_entry->>'kind'='expense';
  insert into heiro_business.audit(actor_id,action,target) values(v_uid,'entry_added',v_id::text);
  return v_id;
end; $$;

create function heiro_business.remove_entry(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=heiro_business.require_owner(); v_month date; v_kind text;
begin
  delete from heiro_business.entries where id=p_id returning month,kind into v_month,v_kind;
  if v_kind='expense' then update heiro_business.monthly_reports set costs_complete=false where month=v_month; end if;
  insert into heiro_business.audit(actor_id,action,target) values(v_uid,'entry_removed',p_id::text);
end; $$;

create function heiro_business.write_report(p_report jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=heiro_business.require_owner(); v_month date:=(p_report->>'month')::date;
begin
  if pg_column_size(p_report)>4096 or v_month<date '2025-01-01' or
    v_month>(date_trunc('month',now())+interval '1 month')::date then raise exception 'INVALID_REPORT'; end if;
  insert into heiro_business.monthly_reports(month,mrr_zar,starting_payers,lost_starting_payers,reference,costs_complete,updated_by)
  values(v_month,nullif(p_report->>'mrr_zar','')::numeric,nullif(p_report->>'starting_payers','')::integer,
    nullif(p_report->>'lost_starting_payers','')::integer,p_report->>'reference',coalesce((p_report->>'costs_complete')::boolean,false),v_uid)
  on conflict(month) do update set mrr_zar=excluded.mrr_zar,starting_payers=excluded.starting_payers,
    lost_starting_payers=excluded.lost_starting_payers,reference=excluded.reference,
    costs_complete=excluded.costs_complete,updated_at=now(),updated_by=v_uid;
  insert into heiro_business.audit(actor_id,action,target) values(v_uid,'report_saved',v_month::text);
end; $$;

create function heiro_business.set_exclusion(p_kind text,p_identifier text,p_reason text,p_excluded boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=heiro_business.require_owner(); v_id uuid;
begin
  if p_kind='account' then
    select id into v_id from auth.users where lower(email)=lower(trim(p_identifier)) or id::text=p_identifier;
  elsif p_kind='family' then
    select id into v_id from public.family_groups where id::text=p_identifier;
  else raise exception 'INVALID_EXCLUSION'; end if;
  if v_id is null and not p_excluded then v_id:=p_identifier::uuid; end if;
  if v_id is null then raise exception 'ACCOUNT_OR_FAMILY_NOT_FOUND'; end if;
  if p_excluded then
    insert into heiro_business.exclusions(kind,subject_id,reason) values(p_kind,v_id,p_reason)
    on conflict(kind,subject_id) do update set reason=excluded.reason;
  else delete from heiro_business.exclusions where kind=p_kind and subject_id=v_id; end if;
  insert into heiro_business.audit(actor_id,action,target) values(v_uid,
    case when p_excluded then 'excluded' else 'included' end,p_kind||':'||v_id::text);
end; $$;

-- A complete financial report is imported atomically, including all currencies.
create function heiro_business.import_proceeds(p_entries jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=heiro_business.require_owner(); v_entry jsonb; v_first jsonb:=p_entries->0;
begin
  if jsonb_typeof(p_entries)<>'array' or jsonb_array_length(p_entries) not between 1 and 100
    or pg_column_size(p_entries)>131072 then raise exception 'INVALID_IMPORT'; end if;
  perform pg_advisory_xact_lock(hashtext('heiro_business.report_import'));
  for v_entry in select value from jsonb_array_elements(p_entries) loop
    if v_entry->>'kind'<>'apple_proceeds' or v_entry->>'category'<>'Apple'
      or v_entry->>'source_hash' is null or v_entry->>'period_start' is null or v_entry->>'period_end' is null
      or v_entry->>'source_hash' is distinct from v_first->>'source_hash'
      or v_entry->>'period_start' is distinct from v_first->>'period_start'
      or v_entry->>'period_end' is distinct from v_first->>'period_end'
      or v_entry->>'month' is distinct from v_first->>'month' then raise exception 'INVALID_IMPORT'; end if;
    if exists(select 1 from heiro_business.entries e where e.kind='apple_proceeds'
      and e.period_start<=(v_entry->>'period_end')::date and e.period_end>=(v_entry->>'period_start')::date
      and e.source_hash is distinct from v_entry->>'source_hash') then raise exception 'OVERLAPPING_APPLE_REPORT'; end if;
    perform heiro_business.write_entry(v_entry);
  end loop;
end; $$;

-- Small invoker wrappers expose only gated, aggregate operations.
create function public.business_import_proceeds(p_entries jsonb) returns void language sql security invoker set search_path='' as $$select heiro_business.import_proceeds(p_entries)$$;
create function public.business_dashboard(p_month date) returns jsonb language sql security invoker set search_path='' as $$select heiro_business.dashboard(p_month)$$;
create function public.business_add_entry(p_entry jsonb) returns uuid language sql security invoker set search_path='' as $$select heiro_business.write_entry(p_entry)$$;
create function public.business_remove_entry(p_id uuid) returns void language sql security invoker set search_path='' as $$select heiro_business.remove_entry(p_id)$$;
create function public.business_save_report(p_report jsonb) returns void language sql security invoker set search_path='' as $$select heiro_business.write_report(p_report)$$;
create function public.business_set_exclusion(p_kind text,p_identifier text,p_reason text,p_excluded boolean) returns void language sql security invoker set search_path='' as $$select heiro_business.set_exclusion(p_kind,p_identifier,p_reason,p_excluded)$$;

revoke all on all functions in schema heiro_business from public,anon,authenticated,service_role;
grant execute on function heiro_business.import_proceeds(jsonb),heiro_business.dashboard(date),heiro_business.write_entry(jsonb),heiro_business.remove_entry(uuid),heiro_business.write_report(jsonb),heiro_business.set_exclusion(text,text,text,boolean) to authenticated;
revoke all on function public.business_import_proceeds(jsonb),public.business_dashboard(date),public.business_add_entry(jsonb),public.business_remove_entry(uuid),public.business_save_report(jsonb),public.business_set_exclusion(text,text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.business_import_proceeds(jsonb),public.business_dashboard(date),public.business_add_entry(jsonb),public.business_remove_entry(uuid),public.business_save_report(jsonb),public.business_set_exclusion(text,text,text,boolean) to authenticated;

-- Already-installed pg_cron; no new service or external request.
do $$begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    perform cron.schedule('heiro-business-daily','10 0 * * *','select heiro_business.capture_daily()');
  end if;
end$$;
