-- Billing checkout lifecycle only. No vault, legacy or family editing policy changes.
alter table public.family_sponsor_reservations
  add column reservation_id uuid not null default gen_random_uuid();

-- Keep the checkout's family association for a later verified restore, even when
-- another checkout replaces its short-lived lock. No receipts or identity text.
create table public.family_sponsor_checkout_attempts (
  reservation_id uuid primary key,
  family_id uuid not null references public.family_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reserved_at timestamptz not null,
  expires_at timestamptz not null,
  released_at timestamptz
);
create index family_sponsor_checkout_attempts_lookup
  on public.family_sponsor_checkout_attempts(family_id,user_id,reserved_at);
create index family_sponsor_checkout_attempts_rate_limit
  on public.family_sponsor_checkout_attempts(user_id,reserved_at);
alter table public.family_sponsor_checkout_attempts enable row level security;
revoke all on public.family_sponsor_checkout_attempts from public,anon,authenticated;
grant all on public.family_sponsor_checkout_attempts to service_role;
insert into public.family_sponsor_checkout_attempts(reservation_id,family_id,user_id,reserved_at,expires_at)
select reservation_id,family_id,user_id,reserved_at,expires_at from public.family_sponsor_reservations;

do $$
declare definition text; marker text := 'reserved_at=now(),expires_at=now()+interval ''15 minutes''';
begin
  select pg_get_functiondef('public.reserve_family_sponsorship(uuid)'::regprocedure) into definition;
  if strpos(definition,marker)=0 then raise exception 'Unexpected sponsorship reservation definition'; end if;
  execute replace(definition,marker,'reservation_id=gen_random_uuid(),'||marker);
end;
$$;

create function public.begin_family_sponsorship(p_family_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare r public.family_sponsor_reservations%rowtype;
begin
  perform public.reserve_family_sponsorship(p_family_id);
  if (select count(*) from public.family_sponsor_checkout_attempts
      where user_id=auth.uid() and reserved_at>now()-interval '1 minute') >= 6 then
    raise exception 'SPONSOR_CHECKOUT_RATE_LIMIT' using errcode='P0001';
  end if;
  select * into strict r from public.family_sponsor_reservations
    where family_id=p_family_id and user_id=auth.uid();
  insert into public.family_sponsor_checkout_attempts(reservation_id,family_id,user_id,reserved_at,expires_at)
  values(r.reservation_id,r.family_id,r.user_id,r.reserved_at,r.expires_at)
  on conflict(reservation_id) do nothing;
  return jsonb_build_object('reservation_id',r.reservation_id,'expires_at',r.expires_at);
end;
$$;
revoke all on function public.begin_family_sponsorship(uuid) from public,anon;
grant execute on function public.begin_family_sponsorship(uuid) to authenticated;

create function public.release_family_sponsorship(p_family_id uuid,p_reservation_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if auth.uid() is null then raise exception 'FAMILY_MEMBERSHIP_REQUIRED' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtext(p_family_id::text));
  -- A late cancellation cannot unlock a different account's or newer checkout.
  update public.family_sponsor_checkout_attempts set released_at=coalesce(released_at,now())
    where reservation_id=p_reservation_id and family_id=p_family_id and user_id=auth.uid();
  delete from public.family_sponsor_reservations
    where reservation_id=p_reservation_id and family_id=p_family_id and user_id=auth.uid();
end;
$$;
revoke all on function public.release_family_sponsorship(uuid,uuid) from public,anon;
grant execute on function public.release_family_sponsorship(uuid,uuid) to authenticated;

create function public.has_family_sponsorship_attempt(p_family uuid,p_user uuid,p_purchase timestamptz)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.family_sponsor_reservations where family_id=p_family
    and user_id=p_user and p_purchase>=reserved_at-interval '1 minute' and p_purchase<=expires_at)
  or exists(select 1 from public.family_sponsor_checkout_attempts where family_id=p_family
    and user_id=p_user and p_purchase>=reserved_at-interval '1 minute'
    and p_purchase<=least(expires_at,coalesce(released_at,expires_at)));
$$;
revoke all on function public.has_family_sponsorship_attempt(uuid,uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.has_family_sponsorship_attempt(uuid,uuid,timestamptz) to service_role;

do $$
declare definition text; marker text := $marker$not exists(select 1 from public.family_sponsor_reservations
      where family_id=v_family and user_id=p_user_id and v_purchase >= reserved_at - interval '1 minute'
        and v_purchase <= expires_at)$marker$;
begin
  select pg_get_functiondef('public.apply_verified_family_subscription(jsonb,uuid,uuid,text,text)'::regprocedure) into definition;
  if strpos(definition,marker)=0 then raise exception 'Unexpected sponsorship verification definition'; end if;
  execute replace(definition,marker,'not public.has_family_sponsorship_attempt(v_family,p_user_id,v_purchase)');
end;
$$;
