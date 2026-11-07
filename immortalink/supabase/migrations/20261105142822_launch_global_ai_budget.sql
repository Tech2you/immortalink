-- USD microdollars. This is an application circuit breaker, not a provider invoice.
create table heiro_security.ai_budget_settings(
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default true,
  daily_limit_microdollars integer not null check(daily_limit_microdollars between 1 and 2000000)
);
insert into heiro_security.ai_budget_settings values(true,true,2000000);
create table heiro_security.ai_budget_days(
  day date primary key, reserved_microdollars integer not null default 0 check(reserved_microdollars>=0),
  denied_requests integer not null default 0, pricing_mismatches integer not null default 0
);
create table heiro_security.ai_budget_reservations(
  id uuid primary key default gen_random_uuid(), day date not null references heiro_security.ai_budget_days(day) on delete cascade,
  kind text not null check(kind in ('chat','embedding','transcription')),
  amount integer not null check(amount between 1 and 200000), settled boolean not null default false
);
alter table heiro_security.ai_budget_settings enable row level security;
alter table heiro_security.ai_budget_days enable row level security;
alter table heiro_security.ai_budget_reservations enable row level security;
revoke all on heiro_security.ai_budget_settings,heiro_security.ai_budget_days,heiro_security.ai_budget_reservations from public,anon,authenticated,service_role;
create function public.reserve_ai_budget(p_kind text,p_amount integer) returns uuid
language plpgsql security definer set search_path='' as $$
declare d date:=(clock_timestamp() at time zone 'UTC')::date; lim integer; active boolean; token uuid;
begin
  if p_kind is null or p_kind not in ('chat','embedding','transcription') or p_amount is null or p_amount not between 1 and 200000 then
    raise exception 'INVALID_AI_RESERVATION'; end if;
  select daily_limit_microdollars,enabled into lim,active from heiro_security.ai_budget_settings where singleton;
  if active is distinct from true then return null; end if;
  insert into heiro_security.ai_budget_days(day) values(d) on conflict do nothing;
  update heiro_security.ai_budget_days set reserved_microdollars=reserved_microdollars+p_amount
    where day=d and reserved_microdollars+p_amount<=lim;
  if not found then
    update heiro_security.ai_budget_days set denied_requests=denied_requests+1 where day=d;
    return null;
  end if;
  insert into heiro_security.ai_budget_reservations(day,kind,amount) values(d,p_kind,p_amount) returning id into token;
  return token;
end; $$;
create function public.settle_ai_budget(p_id uuid,p_amount integer) returns void
language plpgsql security definer set search_path='' as $$
declare r heiro_security.ai_budget_reservations%rowtype;
begin
  if p_amount is null or p_amount<0 then raise exception 'INVALID_AI_SETTLEMENT'; end if;
  select * into r from heiro_security.ai_budget_reservations where id=p_id for update;
  if not found or r.settled then return; end if;
  if p_amount>r.amount then
    -- Unexpected model pricing/usage: retain full reservation and stop new calls.
    update heiro_security.ai_budget_settings set enabled=false where singleton;
    update heiro_security.ai_budget_days set pricing_mismatches=pricing_mismatches+1 where day=r.day;
  else
    update heiro_security.ai_budget_days set reserved_microdollars=reserved_microdollars-(r.amount-p_amount) where day=r.day;
  end if;
  update heiro_security.ai_budget_reservations set settled=true where id=p_id;
end; $$;
revoke all on function public.reserve_ai_budget(text,integer),public.settle_ai_budget(uuid,integer) from public,anon,authenticated;
grant execute on function public.reserve_ai_budget(text,integer),public.settle_ai_budget(uuid,integer) to service_role;

create function public.business_ai_budget_status() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform heiro_business.require_owner();
  select jsonb_build_object('enabled',s.enabled,'limit_usd',s.daily_limit_microdollars/1000000.0,
    'reserved_usd',coalesce(d.reserved_microdollars,0)/1000000.0,'denied_requests',coalesce(d.denied_requests,0),
    'pricing_mismatches',coalesce(d.pricing_mismatches,0),'resets_at',(date_trunc('day',now() at time zone 'UTC')+interval '1 day') at time zone 'UTC') into result
    from heiro_security.ai_budget_settings s left join heiro_security.ai_budget_days d on d.day=(now() at time zone 'UTC')::date where singleton;
  return result;
end; $$;
revoke all on function public.business_ai_budget_status() from public,anon;
grant execute on function public.business_ai_budget_status() to authenticated;
-- Only aggregates and random request IDs are kept; no prompts or transcripts.
do $$ begin
  if exists(select 1 from pg_namespace where nspname='cron') then
    perform cron.schedule('heiro-ai-budget-retention','25 3 * * *',
      $job$delete from heiro_security.ai_budget_days where day<(now() at time zone 'UTC')::date-30$job$);
  end if;
end $$;
