-- Staged only. No schedule, backfill, network request or enabled switch.
create table content_safety.screening_delivery_config (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default false,
  email_enabled boolean not null default false,
  push_enabled boolean not null default false,
  budget_day date not null default (now() at time zone 'UTC')::date,
  email_attempts integer not null default 0 check(email_attempts>=0),
  push_attempts integer not null default 0 check(push_attempts>=0),
  email_daily_limit integer not null default 20 check(email_daily_limit between 1 and 40),
  push_daily_limit integer not null default 200 check(push_daily_limit between 1 and 1000),
  max_pending integer not null default 1000 check(max_pending between 1 and 1000),
  omitted bigint not null default 0 check(omitted>=0)
);
insert into content_safety.screening_delivery_config(singleton) values(true);
create table content_safety.screening_notices (
  id uuid primary key default gen_random_uuid(),
  memory_id uuid unique references public.memories(id) on delete cascade,
  legacy_memory_id uuid unique references public.legacy_memories(id) on delete cascade,
  generation uuid not null,
  scope_id uuid not null,
  family_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  check(num_nonnulls(memory_id,legacy_memory_id)=1)
);
create table content_safety.screening_deliveries (
  id uuid primary key default gen_random_uuid(),
  channel text not null check(channel in ('email','push')),
  case_id uuid unique references content_safety.screening_reviews(id) on delete cascade,
  notice_id uuid references content_safety.screening_notices(id) on delete cascade,
  recipient_id uuid references auth.users(id) on delete cascade,
  token_hash text check(token_hash ~ '^[a-f0-9]{64}$'),
  state text not null default 'pending' check(state in ('pending','leased','sending','accepted','skipped','failed','uncertain')),
  code text,
  attempts integer not null default 0 check(attempts between 0 and 3),
  leases integer not null default 0 check(leases between 0 and 8),
  first_attempt_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  next_attempt_at timestamptz not null default clock_timestamp(),
  lease_id uuid,
  lease_until timestamptz,
  invocation_hash text,
  invocation_expires timestamptz,
  claimed boolean not null default false,
  accepted_at timestamptz,
  unique(notice_id,recipient_id,token_hash),
  check((channel='email' and case_id is not null and notice_id is null and recipient_id is null and token_hash is null)
    or (channel='push' and case_id is null and notice_id is not null and recipient_id is not null and token_hash is not null))
);
create index screening_deliveries_ready on content_safety.screening_deliveries(channel,next_attempt_at,created_at)
  where state in ('pending','leased','sending');
create index screening_deliveries_recipient on content_safety.screening_deliveries(recipient_id);
create unique index screening_deliveries_invocation on content_safety.screening_deliveries(invocation_hash)
  where invocation_hash is not null;
alter table content_safety.screening_delivery_config enable row level security;
alter table content_safety.screening_notices enable row level security;
alter table content_safety.screening_deliveries enable row level security;
revoke all on content_safety.screening_delivery_config,content_safety.screening_notices,content_safety.screening_deliveries
  from public,anon,authenticated,service_role;

-- Only current family members eligible to read the approved source may receive
-- a generic notice. Provider permission is not a publication or push permission.
create function content_safety.screening_notice_audience(p_kind text,p_target uuid,p_generation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare o content_safety.screening_origins; scope uuid; f uuid; authors uuid[]; recipients jsonb;
begin
  select * into o from content_safety.screening_origins where id=p_generation and cleared_generation=id
    and ((p_kind='memory' and memory_id=p_target) or (p_kind='legacy_memory' and legacy_memory_id=p_target));
  if not found or not exists(select 1 from content_safety.screening_controls where enforce_publication) then return null; end if;
  if p_kind='memory' then
    select v.id,v.family_id,array[v.owner_id] into scope,f,authors from public.memories m
      join public.vaults v on v.id=m.vault_id where m.id=p_target and m.share_to_family_feed is true;
  elsif p_kind='legacy_memory' then
    select l.id,l.family_id,array[m.contributor_id,m.last_editor_id] into scope,f,authors
      from public.legacy_memories m join public.legacy_family_members l on l.id=m.legacy_member_id and l.family_id=m.family_id where m.id=p_target;
    authors:=authors||coalesce((select array_agg(u) from public.legacy_memory_photos p
      cross join lateral unnest(array[p.contributor_id,p.last_editor_id]) u where p.legacy_memory_id=p_target),'{}'::uuid[]);
  end if;
  if scope is null or scope<>o.scope_id or f is null or authors is null or array_position(authors,null) is not null
    or exists(select 1 from unnest(authors) a where not exists(select 1 from auth.users where id=a)
      or not exists(select 1 from public.family_members where user_id=a and family_id=f)
      or exists(select 1 from public.account_deletion_jobs where user_id=a))
    or exists(select 1 from content_safety.restrictions r where
      (r.target_kind=p_kind and r.target_id=p_target) or (r.target_kind='family' and r.target_id=f)
      or (r.target_kind=case p_kind when 'memory' then 'vault' else 'legacy_profile' end and r.target_id=scope)
      or (r.target_kind='member' and r.target_id=any(authors))) then return null; end if;
  select coalesce(jsonb_agg(q.user_id order by q.user_id),'[]') into recipients from (
    select distinct fm.user_id from public.family_members fm join auth.users u on u.id=fm.user_id
      where fm.family_id=f and not(fm.user_id=any(authors))
      and not exists(select 1 from public.account_deletion_jobs where user_id=fm.user_id)
      and not exists(select 1 from content_safety.restrictions where target_kind='member' and target_id=fm.user_id)
      and not exists(select 1 from public.member_blocks b where
        (b.blocker_id=fm.user_id and b.blocked_id=any(authors)) or (b.blocked_id=fm.user_id and b.blocker_id=any(authors)))
      and not exists(select 1 from public.family_feed_hidden_vaults h where p_kind='memory' and h.user_id=fm.user_id and h.hidden_vault_id=scope)
  ) q;
  return jsonb_build_object('family_id',f,'scope_id',scope,'recipient_ids',recipients);
end;
$$;

create function content_safety.queue_screening_delivery(p_channel text,p_case uuid,p_notice uuid,p_recipient uuid,p_hash text)
returns void language plpgsql security definer set search_path='' as $$
declare c content_safety.screening_delivery_config;
begin
  select * into c from content_safety.screening_delivery_config where singleton for update;
  if not c.enabled then return; end if;
  if (select count(*) from content_safety.screening_deliveries where state in ('pending','leased','sending'))>=c.max_pending then
    update content_safety.screening_delivery_config set omitted=omitted+1 where singleton;return;
  end if;
  insert into content_safety.screening_deliveries(channel,case_id,notice_id,recipient_id,token_hash)
    values(p_channel,p_case,p_notice,p_recipient,p_hash) on conflict do nothing;
end;
$$;
create function content_safety.capture_screening_email()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  perform content_safety.queue_screening_delivery('email',new.id,null,null,null);return new;
end;
$$;
create trigger screening_review_email after insert on content_safety.screening_reviews
  for each row execute function content_safety.capture_screening_email();

-- One notice per source, not per edit, approval retry or report Restore. Tokens
-- are represented only by hashes here and re-resolved for the same user at send.
create function content_safety.capture_screening_notice()
returns trigger language plpgsql security definer set search_path='' as $$
declare context jsonb; notice uuid; recipient record; total integer;
begin
  if new.cleared_generation is distinct from new.id or old.cleared_generation is not distinct from new.cleared_generation
    or not exists(select 1 from content_safety.screening_delivery_config where enabled) then return new; end if;
  context:=content_safety.screening_notice_audience(case when new.memory_id is null then 'legacy_memory' else 'memory' end,
    coalesce(new.memory_id,new.legacy_memory_id),new.id);
  if context is null then return new; end if;
  insert into content_safety.screening_notices(memory_id,legacy_memory_id,generation,scope_id,family_id)
    values(new.memory_id,new.legacy_memory_id,new.id,new.scope_id,(context->>'family_id')::uuid)
    on conflict do nothing returning id into notice;
  if notice is null then return new; end if;
  total:=0;
  for recipient in select t.user_id,t.token from public.user_push_tokens t
    where context->'recipient_ids' ? t.user_id::text and length(t.token) between 1 and 4096
    order by t.last_seen_at desc,t.token limit 101 loop
    total:=total+1;
    if total>100 then update content_safety.screening_delivery_config set omitted=omitted+1 where singleton;exit; end if;
    perform content_safety.queue_screening_delivery('push',null,notice,recipient.user_id,encode(sha256(convert_to(recipient.token,'UTF8')),'hex'));
  end loop;
  return new;
end;
$$;
create trigger screening_publication_notice after update of cleared_generation on content_safety.screening_origins
  for each row execute function content_safety.capture_screening_notice();

-- Issue a short-lived single-use invocation; callers need server privileges.
-- No reusable server key is placed in a URL, browser or future HTTP queue.
create function public.issue_screening_delivery(p_channel text)
returns text language plpgsql security definer set search_path='' as $$
declare c content_safety.screening_delivery_config; d content_safety.screening_deliveries; token text;
begin
  if p_channel is null or p_channel not in ('email','push') then raise exception 'INVALID_CHANNEL'; end if;
  perform content_safety.media_lifecycle_lock();
  select * into c from content_safety.screening_delivery_config where singleton for update;
  if not c.enabled or not(case p_channel when 'email' then c.email_enabled else c.push_enabled end)
    or not exists(select 1 from content_safety.screening_controls where enforce_publication) then return null; end if;
  update content_safety.screening_deliveries set state='uncertain',code='DISPATCH_UNCONFIRMED',invocation_hash=null
    where channel='push' and state='sending' and lease_until<clock_timestamp();
  update content_safety.screening_deliveries set state='failed',code='REVIEW_REQUIRED',invocation_hash=null
    where state in ('pending','leased','sending') and (lease_until is null or lease_until<clock_timestamp())
    and (attempts>=3 or leases>=8 or first_attempt_at<clock_timestamp()-interval '23 hours' or created_at<clock_timestamp()-interval '7 days');
  update content_safety.screening_deliveries set state='pending',invocation_hash=null
    where ((state='leased') or (state='sending' and channel='email')) and lease_until<clock_timestamp();
  if c.budget_day=(clock_timestamp() at time zone 'UTC')::date
    and (case p_channel when 'email' then c.email_attempts>=c.email_daily_limit else c.push_attempts>=c.push_daily_limit end) then return null; end if;
  select * into d from content_safety.screening_deliveries where channel=p_channel and state='pending' and next_attempt_at<=clock_timestamp()
    order by created_at,id limit 1 for update skip locked;
  if not found then return null; end if;
  token:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','');
  update content_safety.screening_deliveries set state='leased',leases=leases+1,claimed=false,
    lease_id=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes',invocation_hash=encode(sha256(convert_to(token,'UTF8')),'hex'),
    invocation_expires=clock_timestamp()+interval '90 seconds' where id=d.id;
  return token;
end;
$$;
create function public.claim_screening_delivery(p_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d content_safety.screening_deliveries;
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'DELIVERY_UNAUTHORIZED' using errcode='42501'; end if;
  -- Reject invented/expired invocations with an indexed lookup before taking
  -- the lifecycle lock shared with uploads, edits and account deletion.
  if not exists(select 1 from content_safety.screening_deliveries
    where invocation_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex')
    and invocation_expires>clock_timestamp() and lease_until>clock_timestamp() and state='leased' and not claimed) then
    raise exception 'DELIVERY_UNAUTHORIZED' using errcode='42501';
  end if;
  perform content_safety.media_lifecycle_lock();
  select * into d from content_safety.screening_deliveries where invocation_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex')
    and invocation_expires>clock_timestamp() and lease_until>clock_timestamp() and state='leased' and not claimed for update;
  if not found then raise exception 'DELIVERY_UNAUTHORIZED' using errcode='42501'; end if;
  update content_safety.screening_deliveries set claimed=true,invocation_hash=null,
    lease_until=clock_timestamp()+interval '2 minutes' where id=d.id;
  return jsonb_build_object('id',d.id,'lease',d.lease_id,'channel',d.channel);
end;
$$;

create function public.authorize_screening_delivery(p_id uuid,p_lease uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c content_safety.screening_delivery_config; d content_safety.screening_deliveries;
  n content_safety.screening_notices; r content_safety.screening_reviews; context jsonb; token text;
begin
  perform content_safety.media_lifecycle_lock();
  select * into c from content_safety.screening_delivery_config where singleton for update;
  select * into d from content_safety.screening_deliveries where id=p_id for update;
  if not found or d.state<>'leased' or not d.claimed or p_lease is null or p_lease is distinct from d.lease_id
    or d.lease_until<=clock_timestamp() then return null; end if;
  if not c.enabled or not(case d.channel when 'email' then c.email_enabled else c.push_enabled end)
    or not exists(select 1 from content_safety.screening_controls where enforce_publication) then return null; end if;
  if d.channel='email' then
    select * into r from content_safety.screening_reviews where id=d.case_id;
    if r.state in ('open','reviewing') and exists(select 1 from content_safety.screening_origins where id=r.generation)
      and (content_safety.screening_review_snapshot(r.id)->>'available')::boolean then
      context:=jsonb_build_object('case_id',r.id);
    end if;
  else
    select * into n from content_safety.screening_notices where id=d.notice_id;
    context:=content_safety.screening_notice_audience(case when n.memory_id is null then 'legacy_memory' else 'memory' end,
      coalesce(n.memory_id,n.legacy_memory_id),n.generation);
    if context is not null and (context->>'family_id')::uuid=n.family_id and (context->>'scope_id')::uuid=n.scope_id
      and context->'recipient_ids' ? d.recipient_id::text then
      select t.token into token from public.user_push_tokens t where t.user_id=d.recipient_id
        and encode(sha256(convert_to(t.token,'UTF8')),'hex')=d.token_hash and length(t.token) between 1 and 4096;
    end if;
    context:=case when token is not null then jsonb_build_object('token',token,'family_id',n.family_id,'event_id',n.id) else null end;
  end if;
  if context is null then
    update content_safety.screening_deliveries set state='skipped',code='NO_LONGER_ELIGIBLE',invocation_hash=null where id=d.id;return null;
  end if;
  if d.attempts>=3 or d.first_attempt_at<clock_timestamp()-interval '23 hours' then
    update content_safety.screening_deliveries set state='failed',code='REVIEW_REQUIRED' where id=d.id;return null;
  end if;
  if c.budget_day<>(clock_timestamp() at time zone 'UTC')::date then
    update content_safety.screening_delivery_config set budget_day=(clock_timestamp() at time zone 'UTC')::date,email_attempts=0,push_attempts=0 where singleton;
    c.email_attempts:=0;c.push_attempts:=0;
  end if;
  if (case d.channel when 'email' then c.email_attempts>=c.email_daily_limit else c.push_attempts>=c.push_daily_limit end) then return null; end if;
  update content_safety.screening_delivery_config set email_attempts=email_attempts+case d.channel when 'email' then 1 else 0 end,
    push_attempts=push_attempts+case d.channel when 'push' then 1 else 0 end where singleton;
  update content_safety.screening_deliveries set state='sending',attempts=attempts+1,first_attempt_at=coalesce(first_attempt_at,clock_timestamp()) where id=d.id;
  return context||jsonb_build_object('id',d.id,'channel',d.channel,'send_before',clock_timestamp()+interval '15 seconds');
end;
$$;

create function public.finish_screening_delivery(p_id uuid,p_lease uuid,p_result text,p_retry_seconds integer default 60)
returns boolean language plpgsql security definer set search_path='' as $$
declare d content_safety.screening_deliveries; next_state text;
begin
  if p_result is null or p_result not in ('ACCEPTED','RETRY','REJECTED','UNKNOWN') or p_retry_seconds is null
    or p_retry_seconds not between 60 and 86400 then raise exception 'INVALID_DELIVERY_RESULT'; end if;
  perform content_safety.media_lifecycle_lock();
  select * into d from content_safety.screening_deliveries where id=p_id for update;
  if not found or d.state<>'sending' or p_lease is null or d.lease_id is distinct from p_lease or d.lease_until<=clock_timestamp() then return false; end if;
  next_state:=case when p_result='ACCEPTED' then 'accepted' when p_result='UNKNOWN' and d.channel='push' then 'uncertain'
    when p_result in ('RETRY','UNKNOWN') and d.attempts<3 and d.first_attempt_at>clock_timestamp()-interval '23 hours' then 'pending' else 'failed' end;
  update content_safety.screening_deliveries set state=next_state,code=p_result,
    accepted_at=case when p_result='ACCEPTED' then clock_timestamp() end,
    next_attempt_at=clock_timestamp()+make_interval(secs=>greatest(p_retry_seconds,60*power(2,d.attempts)::integer)),
    lease_until=null,lease_id=null,invocation_hash=null where id=d.id;
  return true;
end;
$$;

-- Explicit dispatcher only: this migration never installs or starts a schedule.
-- Platform HTTP queues receive a one-use token, never a reusable credential.
create function public.dispatch_screening_delivery(p_channel text)
returns bigint language plpgsql security definer set search_path='' as $$
declare token text; request_id bigint;
begin
  token:=public.issue_screening_delivery(p_channel);
  if token is null then return null; end if;
  select net.http_post(
    url:='https://vbzyvaylfdhwowdbodmk.supabase.co/functions/v1/send_screening_delivery',
    headers:=jsonb_build_object('Content-Type','application/json','x-screening-delivery-token',token),
    body:='{}'::jsonb,timeout_milliseconds:=55000
  ) into request_id;
  return request_id;
end;
$$;

create function public.screening_delivery_health()
returns jsonb language sql security definer set search_path='' as $$
  select jsonb_build_object('enabled',c.enabled,'email_enabled',c.email_enabled,'push_enabled',c.push_enabled,
    'omitted',c.omitted,'attention',(select count(*) from content_safety.screening_deliveries where state in ('failed','uncertain')
      or (state in ('pending','leased','sending') and created_at<clock_timestamp()-interval '15 minutes')),
    'pending',(select count(*) from content_safety.screening_deliveries where state in ('pending','leased','sending')),
    'accepted',(select count(*) from content_safety.screening_deliveries where state='accepted'),
    'email_attempts',case when c.budget_day=(clock_timestamp() at time zone 'UTC')::date then c.email_attempts else 0 end,
    'push_attempts',case when c.budget_day=(clock_timestamp() at time zone 'UTC')::date then c.push_attempts else 0 end,
    'email_daily_limit',c.email_daily_limit,'push_daily_limit',c.push_daily_limit)
  from content_safety.screening_delivery_config c where singleton;
$$;

-- Old clients must not bypass the outbox by calling the immediate sender after
-- approval. Existing archives and family-joined notifications retain their route.
create function public.memory_notification_route(p_memory uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare audience jsonb;
begin
  perform content_safety.media_lifecycle_lock();
  audience:=public.memory_notification_audience(p_memory,p_actor);
  return audience||jsonb_build_object('delivery_mode',case when exists(select 1 from content_safety.screening_controls where enforce_publication)
    and exists(select 1 from content_safety.screening_origins where memory_id=p_memory) then 'outbox' else 'direct' end);
end;
$$;
revoke all on function content_safety.screening_notice_audience(text,uuid,uuid),content_safety.queue_screening_delivery(text,uuid,uuid,uuid,text),
  content_safety.capture_screening_email(),content_safety.capture_screening_notice() from public,anon,authenticated,service_role;
revoke all on function public.issue_screening_delivery(text),public.claim_screening_delivery(text),public.authorize_screening_delivery(uuid,uuid),
  public.finish_screening_delivery(uuid,uuid,text,integer),public.screening_delivery_health(),public.memory_notification_route(uuid,uuid),public.dispatch_screening_delivery(text)
  from public,anon,authenticated,service_role;
grant execute on function public.issue_screening_delivery(text),public.claim_screening_delivery(text),public.authorize_screening_delivery(uuid,uuid),
  public.finish_screening_delivery(uuid,uuid,text,integer),public.screening_delivery_health(),public.memory_notification_route(uuid,uuid),public.dispatch_screening_delivery(text) to service_role;
