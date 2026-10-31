-- Explicit, Apple-verified moves by the original payer. No membership/content
-- edits, no checkout and no change to price, renewal or subscription group.
create table heiro_billing.detached_contributions (
 original_id text primary key, purchaser_id uuid not null references auth.users on delete cascade,
 entitlement jsonb not null, period_start date not null,
 ai_used integer not null, transcription_used integer not null
);
create table heiro_billing.contribution_move_quotes (
 purchaser_id uuid primary key references auth.users on delete cascade,
 id uuid not null unique default gen_random_uuid(), original_id text not null,
 target_family uuid not null references public.family_groups on delete cascade,
 snapshot jsonb not null, preview jsonb not null,
 expires_at timestamptz not null default now()+interval '10 minutes'
);
create table heiro_billing.contribution_moves (
 id uuid primary key, purchaser_id uuid references auth.users on delete set null,
 original_id text not null, source_family uuid, target_family uuid not null,
 period_start date not null, ai_debit integer not null, ai_credit integer not null,
 transcription_debit integer not null, transcription_credit integer not null,
 result jsonb not null, created_at timestamptz not null default now()
);
create index detached_contribution_payer on heiro_billing.detached_contributions(purchaser_id);
create index contribution_quote_family on heiro_billing.contribution_move_quotes(target_family);
create index contribution_move_payer on heiro_billing.contribution_moves(purchaser_id);
create table heiro_billing.contribution_move_checks (
 purchaser_id uuid primary key references auth.users on delete cascade,
 window_start timestamptz not null, checks integer not null
);
alter table heiro_billing.contribution_move_checks enable row level security;
revoke all on heiro_billing.contribution_move_checks from public,anon,authenticated;
create index contribution_moves_chain on heiro_billing.contribution_moves(original_id,created_at);
alter table heiro_billing.detached_contributions enable row level security;
alter table heiro_billing.contribution_move_quotes enable row level security;
alter table heiro_billing.contribution_moves enable row level security;
revoke all on heiro_billing.detached_contributions,heiro_billing.contribution_move_quotes,
 heiro_billing.contribution_moves from public,anon,authenticated;

-- Same pooling policy as everroot_limits, excluding only the moved chain.
create function heiro_billing.quota_without(p_family uuid,p_original text,p_metric text)
returns integer language sql stable security definer set search_path='' as $$
 with active as(select plan,provider,heiro_billing.tier_limits(plan) limits
  from public.family_entitlements where family_id=p_family
  and apple_original_transaction_id is distinct from p_original
  and status in ('active','grace_period') and (current_period_end is null or current_period_end>now()))
 select least(2147483647,greatest(
  coalesce(sum((limits->>p_metric)::bigint) filter(where provider='apple'),0),
  coalesce(max((limits->>p_metric)::bigint), (heiro_billing.tier_limits('free')->>p_metric)::bigint)))::integer from active;
$$;
create function heiro_billing.usage_share(p_used integer,p_limit integer,p_grant integer)
returns integer language sql immutable set search_path='' as $$
 select least(p_grant,ceil(greatest(0,p_used)::numeric*p_grant/greatest(1,p_limit)))::integer;
$$;

-- Keep only billing/allowance data when the last member deletes the old tree.
create function heiro_billing.preserve_detached_contribution() returns trigger
language plpgsql security definer set search_path='' as $$
declare p date:=public.everroot_period_start(); l jsonb; t jsonb; a integer; s integer;
begin
 if old.provider='apple' and old.apple_original_transaction_id is not null
   and old.billing_owner_user_id is not null and exists(select 1 from auth.users where id=old.billing_owner_user_id) and old.status in ('active','grace_period')
   and old.current_period_end>now() then
  perform pg_advisory_xact_lock(hashtext(old.family_id::text));
  perform pg_advisory_xact_lock(hashtext('family:'||old.family_id||':ai:'||p));
  perform pg_advisory_xact_lock(hashtext('family:'||old.family_id||':transcription:'||p));
  l:=public.everroot_limits(old.family_id); t:=heiro_billing.tier_limits(old.plan);
  select coalesce(max(used_count),0) into a from public.everroot_ai_usage_periods where scope_type='family' and scope_id=old.family_id and period_start=p;
  select coalesce(max(used_seconds),0) into s from public.everroot_transcription_usage_periods where scope_type='family' and scope_id=old.family_id and period_start=p;
  insert into heiro_billing.detached_contributions values(old.apple_original_transaction_id,old.billing_owner_user_id,to_jsonb(old),p,
   heiro_billing.usage_share(a,(l->>'ai_responses_monthly')::integer,(t->>'ai_responses_monthly')::integer),
   heiro_billing.usage_share(s,(l->>'transcription_seconds_monthly')::integer,(t->>'transcription_seconds_monthly')::integer))
  on conflict(original_id) do update set purchaser_id=excluded.purchaser_id,entitlement=excluded.entitlement,
   period_start=excluded.period_start,ai_used=excluded.ai_used,transcription_used=excluded.transcription_used;
 end if;
 return old;
end $$;
create trigger preserve_detached_apple_contribution before delete on public.family_entitlements
for each row execute function heiro_billing.preserve_detached_contribution();

create function heiro_billing.move_candidate(p_user uuid,p_family uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r jsonb;
begin
 if p_user is null or not exists(select 1 from public.family_members where family_id=p_family and user_id=p_user) then
  raise exception 'FAMILY_MEMBERSHIP_REQUIRED'; end if;
 select jsonb_build_object('original_id',b.original_transaction_id,'environment',b.environment,'family_id',b.family_id) into r
 from public.apple_sponsor_bindings b
 left join public.family_entitlements e on e.apple_original_transaction_id=b.original_transaction_id
 left join heiro_billing.detached_contributions d on d.original_id=b.original_transaction_id and d.purchaser_id=p_user
 where b.purchaser_id=p_user and not b.retired and b.family_id is distinct from p_family
 and not exists(select 1 from public.family_members where family_id=b.family_id and user_id=p_user)
 and (e.current_period_end>now() and e.status in ('active','grace_period')
   or b.family_id is null and d.entitlement->>'status' in ('active','grace_period') and (d.entitlement->>'current_period_end')::timestamptz>now())
 order by b.last_purchase_at desc nulls last limit 1;
 return r;
end $$;
create function public.get_apple_contribution_move_candidate(p_user_id uuid,p_family_id uuid,p_confirmation_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o text; attempts integer;
begin
 insert into heiro_billing.contribution_move_checks values(p_user_id,now(),1)
 on conflict(purchaser_id) do update set
 checks=case when contribution_move_checks.window_start<=now()-interval '1 minute' then 1 else contribution_move_checks.checks+1 end,
 window_start=case when contribution_move_checks.window_start<=now()-interval '1 minute' then now() else contribution_move_checks.window_start end
 returning checks into attempts;
 if attempts>20 then raise exception 'APPLE_MOVE_RATE_LIMIT'; end if;
 if p_confirmation_id is null then return heiro_billing.move_candidate(p_user_id,p_family_id); end if;
 if not exists(select 1 from public.family_members where family_id=p_family_id and user_id=p_user_id) then raise exception 'FAMILY_MEMBERSHIP_REQUIRED'; end if;
 select original_id into o from heiro_billing.contribution_move_quotes where id=p_confirmation_id and purchaser_id=p_user_id and target_family=p_family_id;
 if o is null then select original_id into o from heiro_billing.contribution_moves where id=p_confirmation_id and purchaser_id=p_user_id and target_family=p_family_id; end if;
 if o is null then raise exception 'APPLE_MOVE_STALE'; end if;
 return (select jsonb_build_object('original_id',original_transaction_id,'environment',environment,'family_id',family_id) from public.apple_sponsor_bindings where original_transaction_id=o and purchaser_id=p_user_id);
end $$;
revoke all on function public.get_apple_contribution_move_candidate(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.get_apple_contribution_move_candidate(uuid,uuid,uuid) to service_role;

-- Preserve renewal/refund state for an active payer between families.
create function heiro_billing.refresh_detached_from_apple(p_transaction jsonb,p_notification text) returns void
language plpgsql security definer set search_path='' as $$
declare
 o text:=p_transaction->>'originalTransactionId'; b public.apple_sponsor_bindings%rowtype;
 e jsonb; plan text; status text; purchased timestamptz:=to_timestamp((p_transaction->>'purchaseDate')::numeric/1000);
 signed timestamptz:=to_timestamp((p_transaction->>'signedDate')::numeric/1000);
 expiry timestamptz:=to_timestamp((p_transaction->>'expiresDate')::numeric/1000);
begin
 select * into b from public.apple_sponsor_bindings where original_transaction_id=o;
 if not found or b.retired or b.family_id is not null or lower(p_transaction->>'appAccountToken') is distinct from b.purchaser_id::text
  or lower(p_transaction->>'environment') is distinct from b.environment or purchased<b.last_purchase_at
  or signed<b.last_signed_at then return; end if;
 plan:=case p_transaction->>'productId' when 'everroots.family.monthly' then 'everroot_family' when 'everroots.family.annual' then 'everroot_family'
 when 'everroots.legacy.monthly' then 'everroot_legacy' when 'everroots.legacy.annual' then 'everroot_legacy' end;
 if plan is null then return; end if;
 status:=case when p_transaction->>'revocationDate' is not null or p_notification in ('REFUND','REVOKE') then 'revoked' when expiry<=now() then 'expired' else 'active' end;
 update heiro_billing.detached_contributions set entitlement=entitlement || jsonb_build_object('plan',plan,'status',status,
  'current_period_end',expiry,'apple_product_id',p_transaction->>'productId','provider_entitlement_id',p_transaction->>'transactionId')
 where original_id=o and purchaser_id=b.purchaser_id;
 if found then update public.apple_sponsor_bindings set last_purchase_at=purchased,last_signed_at=signed where original_transaction_id=o; end if;
end $$;
-- This entry point is already restricted to the service role and verified Apple
-- payloads. Normal current-family purchases keep their existing implementation.
do $$ declare definition text; marker text:='    v_family := v_binding.family_id;'; begin
 definition:=pg_get_functiondef('public.apply_verified_family_subscription_internal(jsonb,uuid,uuid,text,text)'::regprocedure);
 if position(marker in definition)=0 then raise exception 'Unexpected Apple binding implementation'; end if;
 execute replace(definition,marker,marker||chr(10)||'    if p_source=''server_notification'' and v_family is null and not v_binding.retired then perform heiro_billing.refresh_detached_from_apple(p_transaction,p_notification_type); end if;');
end $$;

-- Preserve the existing summary; add only an authenticated payer's move offer.
alter function public.get_family_sponsorship(uuid) set schema heiro_billing;
create function public.get_family_sponsorship(p_family_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select heiro_billing.get_family_sponsorship(p_family_id) || jsonb_build_object(
 'can_move_contribution',heiro_billing.move_candidate(auth.uid(),p_family_id) is not null);
$$;
revoke all on function public.get_family_sponsorship(uuid) from public,anon;
grant execute on function public.get_family_sponsorship(uuid) to authenticated;

create function public.move_verified_apple_contribution(p_transaction jsonb,p_user_id uuid,p_family_id uuid,p_confirmation_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 o text:=p_transaction->>'originalTransactionId'; env text:=lower(p_transaction->>'environment');
 expiry timestamptz:=to_timestamp((p_transaction->>'expiresDate')::numeric/1000);
 purchase_at timestamptz:=to_timestamp((p_transaction->>'purchaseDate')::numeric/1000);
 signed_at timestamptz:=to_timestamp((p_transaction->>'signedDate')::numeric/1000);
 b public.apple_sponsor_bindings%rowtype; e public.family_entitlements%rowtype;
 d heiro_billing.detached_contributions%rowtype; q heiro_billing.contribution_move_quotes%rowtype;
 prior heiro_billing.contribution_moves%rowtype;
 source uuid; f uuid; p date:=public.everroot_period_start(); plan text; tier jsonb; l jsonb;
 au integer:=0; su integer:=0; ac integer:=0; sc integer:=0; ad integer:=0; sd integer:=0;
 ag integer; sg integer; version integer; snap jsonb; preview jsonb; result jsonb;
begin
 if p_user_id is null or o is null or env is null or env not in ('sandbox','production')
  or p_transaction->>'bundleId' is distinct from 'com.everroots.app'
  or lower(p_transaction->>'appAccountToken') is distinct from p_user_id::text
  or expiry is null or expiry<=now() or purchase_at is null or purchase_at>=expiry
  or signed_at is null or signed_at>now()+interval '1 minute'
  or p_transaction->>'revocationDate' is not null then raise exception 'APPLE_MOVE_UNAVAILABLE'; end if;
 plan:=case p_transaction->>'productId' when 'everroots.family.monthly' then 'everroot_family'
 when 'everroots.family.annual' then 'everroot_family' when 'everroots.legacy.monthly' then 'everroot_legacy'
 when 'everroots.legacy.annual' then 'everroot_legacy' end;
 if plan is null then raise exception 'APPLE_MOVE_UNAVAILABLE'; end if;
 perform pg_advisory_xact_lock(hashtext('apple:'||o));
 perform pg_advisory_xact_lock(hashtext('sponsor-user:'||p_user_id));
 select * into b from public.apple_sponsor_bindings where original_transaction_id=o;
 if not found or b.purchaser_id is distinct from p_user_id or b.environment is distinct from env
   or b.retired or purchase_at<b.last_purchase_at or signed_at<b.last_signed_at then raise exception 'APPLE_MOVE_UNAVAILABLE'; end if;
 for f in select distinct id from unnest(array[b.family_id,p_family_id]) id where id is not null order by id loop
  perform pg_advisory_xact_lock(hashtext(f::text));
 end loop;
 -- Family deletion/leave also locks the family. Re-read after acquiring it.
 select * into b from public.apple_sponsor_bindings where original_transaction_id=o;
 if b.purchaser_id is distinct from p_user_id or b.retired then raise exception 'APPLE_MOVE_UNAVAILABLE'; end if;
 if not exists(select 1 from public.family_members where family_id=p_family_id and user_id=p_user_id) then raise exception 'FAMILY_MEMBERSHIP_REQUIRED'; end if;
 select * into prior from heiro_billing.contribution_moves where id=p_confirmation_id;
 if found then
  if prior.purchaser_id=p_user_id and prior.original_id=o and prior.target_family=p_family_id and b.family_id=p_family_id then return prior.result; end if;
  raise exception 'APPLE_MOVE_STALE';
 end if;
 if b.family_id=p_family_id or exists(select 1 from public.family_members where family_id=b.family_id and user_id=p_user_id) then raise exception 'APPLE_MOVE_UNAVAILABLE'; end if;
 if exists(select 1 from public.family_sponsor_reservations where user_id=p_user_id and expires_at>now()) then raise exception 'SPONSOR_PURCHASE_IN_PROGRESS'; end if;
 if exists(select 1 from public.family_entitlements where provider='apple' and billing_owner_user_id=p_user_id
  and apple_original_transaction_id is distinct from o and status in ('active','grace_period') and current_period_end>now()) then raise exception 'APPLE_MOVE_UNAVAILABLE'; end if;
 if env='sandbox' and exists(select 1 from public.family_entitlements where family_id in (b.family_id,p_family_id) and apple_environment='production') then raise exception 'APPLE_ENVIRONMENT_MISMATCH'; end if;
 select * into e from public.family_entitlements where apple_original_transaction_id=o;
 if not found then
  select * into d from heiro_billing.detached_contributions where original_id=o and purchaser_id=p_user_id;
  if not found or b.family_id is not null then raise exception 'APPLE_MOVE_UNAVAILABLE'; end if;
  e:=jsonb_populate_record(null::public.family_entitlements,d.entitlement);
 elsif e.family_id is distinct from b.family_id or e.billing_owner_user_id is distinct from p_user_id or e.status in ('refunded','revoked') then
  raise exception 'APPLE_MOVE_UNAVAILABLE';
 end if;
 if e.status not in ('active','grace_period') then raise exception 'APPLE_MOVE_UNAVAILABLE'; end if;
 -- A concurrent upgrade must first settle through the existing purchase handler.
 if e.apple_product_id is distinct from p_transaction->>'productId' or e.current_period_end is distinct from expiry then raise exception 'APPLE_MOVE_STALE'; end if;
 source:=b.family_id; version:=e.storage_model_version; tier:=heiro_billing.tier_limits(plan);
 ag:=(tier->>'ai_responses_monthly')::integer; sg:=(tier->>'transcription_seconds_monthly')::integer;
 for f in select distinct id from unnest(array[source,p_family_id]) id where id is not null order by id loop
  perform pg_advisory_xact_lock(hashtext('family:'||f||':ai:'||p));
  perform pg_advisory_xact_lock(hashtext('family:'||f||':transcription:'||p));
 end loop;
 if source is not null then
  l:=public.everroot_limits(source);
  select coalesce(max(used_count),0) into au from public.everroot_ai_usage_periods where scope_type='family' and scope_id=source and period_start=p;
  select coalesce(max(used_seconds),0) into su from public.everroot_transcription_usage_periods where scope_type='family' and scope_id=source and period_start=p;
  ad:=heiro_billing.usage_share(au,(l->>'ai_responses_monthly')::integer,ag);
  sd:=heiro_billing.usage_share(su,(l->>'transcription_seconds_monthly')::integer,sg);
  -- Credit no more than the old family's lost quota; otherwise switching the
  -- last payer could repeatedly regenerate the free allowance.
  ac:=least(ad,au,greatest(0,(l->>'ai_responses_monthly')::integer-heiro_billing.quota_without(source,o,'ai_responses_monthly')));
  sc:=least(sd,su,greatest(0,(l->>'transcription_seconds_monthly')::integer-heiro_billing.quota_without(source,o,'transcription_seconds_monthly')));
 else
  ad:=case when d.period_start=p then least(ag,d.ai_used) else 0 end;
  sd:=case when d.period_start=p then least(sg,d.transcription_used) else 0 end;
 end if;
 snap:=jsonb_build_object('binding',to_jsonb(b),'entitlement',jsonb_build_object('id',e.id,'plan',e.plan,'end',e.current_period_end,'version',version,'status',e.status),
  'period',p,'ai_used',au,'transcription_used',su,'ai_debit',ad,'ai_credit',ac,'transcription_debit',sd,'transcription_credit',sc);
 preview:=jsonb_build_object('storage_bytes',heiro_billing.storage_grant(plan,version),'paid_until',expiry,
  'ai_remaining',ag-ad,'transcription_seconds_remaining',sg-sd,'previous_family_exists',source is not null);
 if p_confirmation_id is null then
  insert into heiro_billing.contribution_move_quotes(purchaser_id,original_id,target_family,snapshot,preview)
  values(p_user_id,o,p_family_id,snap,preview)
  on conflict(purchaser_id) do update set id=gen_random_uuid(),original_id=o,target_family=p_family_id,
   snapshot=snap,preview=excluded.preview,expires_at=now()+interval '10 minutes' returning * into q;
  return preview || jsonb_build_object('confirmation_id',q.id);
 end if;
 select * into q from heiro_billing.contribution_move_quotes where id=p_confirmation_id and purchaser_id=p_user_id;
 if not found or q.expires_at<=now() or q.original_id<>o or q.target_family<>p_family_id or q.snapshot is distinct from snap then raise exception 'APPLE_MOVE_STALE'; end if;
 update public.everroot_ai_usage_periods set used_count=used_count-ac where scope_type='family' and scope_id=source and period_start=p;
 update public.everroot_transcription_usage_periods set used_seconds=used_seconds-sc where scope_type='family' and scope_id=source and period_start=p;
 insert into public.everroot_ai_usage_periods(scope_type,scope_id,period_start,used_count) values('family',p_family_id,p,ad)
 on conflict(scope_type,scope_id,period_start) do update set used_count=public.everroot_ai_usage_periods.used_count+excluded.used_count;
 insert into public.everroot_transcription_usage_periods(scope_type,scope_id,period_start,used_seconds) values('family',p_family_id,p,sd)
 on conflict(scope_type,scope_id,period_start) do update set used_seconds=public.everroot_transcription_usage_periods.used_seconds+excluded.used_seconds;
 update public.apple_sponsor_bindings set family_id=p_family_id,last_purchase_at=purchase_at,last_signed_at=signed_at where original_transaction_id=o;
 if source is not null then
  update public.family_entitlements set family_id=p_family_id,updated_at=now() where apple_original_transaction_id=o;
 else
  insert into public.family_entitlements(family_id,plan,status,provider,billing_owner_user_id,current_period_end,
   apple_original_transaction_id,apple_product_id,apple_environment,provider_subscription_id,provider_entitlement_id,storage_model_version,cancel_at_period_end)
  values(p_family_id,plan,'active','apple',p_user_id,expiry,o,e.apple_product_id,env,o,p_transaction->>'transactionId',version,e.cancel_at_period_end);
 end if;
 result:=jsonb_build_object('moved',true,'paid_until',expiry);
 insert into heiro_billing.contribution_moves values(p_confirmation_id,p_user_id,o,source,p_family_id,p,ad,ac,sd,sc,result,now());
 delete from heiro_billing.contribution_move_quotes where id=p_confirmation_id;
 delete from heiro_billing.detached_contributions where original_id=o;
 return result;
end $$;
revoke all on function public.move_verified_apple_contribution(jsonb,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.move_verified_apple_contribution(jsonb,uuid,uuid,uuid) to service_role;
revoke all on function heiro_billing.quota_without(uuid,text,text),
 heiro_billing.usage_share(integer,integer,integer),
 heiro_billing.preserve_detached_contribution(),
 heiro_billing.move_candidate(uuid,uuid),
 heiro_billing.refresh_detached_from_apple(jsonb,text),
 heiro_billing.get_family_sponsorship(uuid) from public,anon,authenticated;

-- Resolve paid scope and consume quota under the same family lock as a move.
-- Retain all existing membership checks, read-only guards and burst protection.
do $$ declare s regprocedure; definition text; marker text:='  perform public.everroot_assert_family_writable(v_family_id);';
begin
 foreach s in array array['public.everroot_consume_ai_usage(uuid,uuid,integer)'::regprocedure,'public.everroot_consume_transcription_usage(uuid,uuid,integer)'::regprocedure] loop
  definition:=pg_get_functiondef(s);
  if position(marker in definition)=0 then raise exception 'Unexpected quota guard for %',s; end if;
  execute replace(definition,marker,'  if v_family_id is not null then perform pg_advisory_xact_lock(hashtext(v_family_id::text)); end if;'||chr(10)||marker);
 end loop;
end $$;
