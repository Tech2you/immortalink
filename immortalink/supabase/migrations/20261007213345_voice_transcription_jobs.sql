create table public.voice_transcription_jobs (
  scope_id uuid not null,
  content_hash text not null check(content_hash ~ '^[0-9a-f]{64}$'),
  requested_by uuid not null references auth.users(id) on delete cascade,
  token uuid not null,
  status text not null default 'processing' check(status in ('processing','succeeded','failed')),
  transcript text,
  seconds integer not null check(seconds between 1 and 120),
  created_at timestamptz not null default now(),
  primary key(scope_id,content_hash)
);
create table public.voice_transcription_daily_usage (
  day date primary key,
  reserved_seconds integer not null default 0
);
alter table public.voice_transcription_jobs enable row level security;
alter table public.voice_transcription_daily_usage enable row level security;
revoke all on public.voice_transcription_jobs,public.voice_transcription_daily_usage from public,anon,authenticated;
grant all on public.voice_transcription_jobs,public.voice_transcription_daily_usage to service_role;

create function public.claim_voice_transcription(p_scope uuid,p_hash text,p_user uuid,p_token uuid,p_seconds integer)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.voice_transcription_jobs%rowtype; d date:=(now() at time zone 'UTC')::date; used integer;
begin
  insert into public.voice_transcription_jobs(scope_id,content_hash,requested_by,token,seconds)
    values(p_scope,p_hash,p_user,p_token,p_seconds) on conflict do nothing returning * into j;
  if not found then
    select * into j from public.voice_transcription_jobs where scope_id=p_scope and content_hash=p_hash;
    return jsonb_build_object('claimed',false,'status',j.status,'transcript',j.transcript);
  end if;
  -- Conservative application-wide backstop: reserve the full two-minute maximum
  -- per paid request, independently of client duration and per-family allowances.
  insert into public.voice_transcription_daily_usage(day) values(d) on conflict do nothing;
  update public.voice_transcription_daily_usage set reserved_seconds=reserved_seconds+120
    where day=d and reserved_seconds+120<=7200 returning reserved_seconds into used;
  if not found then raise exception 'TRANSCRIPTION_DAILY_CAP'; end if;
  return jsonb_build_object('claimed',true,'status','processing');
end;
$$;
revoke all on function public.claim_voice_transcription(uuid,text,uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.claim_voice_transcription(uuid,text,uuid,uuid,integer) to service_role;

-- Only release reservations before contacting the provider. This prevents a
-- caller with exhausted quota from consuming the whole application's backstop.
create function public.release_voice_transcription(p_scope uuid,p_hash text,p_token uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare started timestamptz;
begin
  delete from public.voice_transcription_jobs where scope_id=p_scope and content_hash=p_hash
    and token=p_token and status='processing' returning created_at into started;
  if found then
    update public.voice_transcription_daily_usage set reserved_seconds=greatest(0,reserved_seconds-120)
      where day=(started at time zone 'UTC')::date;
  end if;
end;
$$;
revoke all on function public.release_voice_transcription(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.release_voice_transcription(uuid,text,uuid) to service_role;
