-- Bound new/changed text without truncating saved content or changing read access.
create schema if not exists heiro_security;
revoke all on schema heiro_security from public,anon,authenticated;

create function heiro_security.bound_saved_text() returns trigger
language plpgsql set search_path='' as $$
declare item record; fresh jsonb:=to_jsonb(new); prior jsonb; ceiling integer;
begin
  if tg_op='UPDATE' then prior:=to_jsonb(old); end if;
  for item in select * from jsonb_each(fresh) loop
    ceiling:=case item.key
      when 'body' then 50000 when 'about_me_text' then 10000
      when 'transcript' then 20000 when 'prompt_text' then 500
      when 'title' then 500 when 'name' then 500
      when 'memory_date_label' then 2000 when 'people' then 2000
      when 'location' then 2000 when 'mood' then 2000 else null end;
    if ceiling is not null and (tg_op='INSERT' or item.value is distinct from prior->item.key)
      and char_length(fresh->>item.key)>ceiling then
      raise exception 'TEXT_LIMIT_EXCEEDED' using errcode='22001',
        detail=format('%s allows at most %s characters.',item.key,ceiling);
    end if;
  end loop;
  return new;
end; $$;
revoke all on function heiro_security.bound_saved_text() from public,anon,authenticated;
do $$ declare t text; begin
  foreach t in array array['memories','legacy_memories','vaults','legacy_family_members',
    'memory_voice_notes','legacy_memory_voice_notes'] loop
    execute format('create trigger launch_text_bounds before insert or update on public.%I for each row execute function heiro_security.bound_saved_text()',t);
  end loop;
end; $$;

create table heiro_security.memory_index_state(
  memory_id uuid primary key references public.memories(id) on delete cascade,
  source_hash text not null,
  chunk_count integer not null check(chunk_count between 0 and 285)
);
create table heiro_security.index_rate(
  user_id uuid primary key references auth.users(id) on delete cascade,
  minute timestamptz not null,
  minute_count integer not null,
  day date not null,
  day_count integer not null
);
alter table heiro_security.memory_index_state enable row level security;
alter table heiro_security.index_rate enable row level security;
revoke all on heiro_security.memory_index_state,heiro_security.index_rate from public,anon,authenticated,service_role;

-- Only the authenticated Edge handlers may call this. They first read the source
-- through the caller's RLS client. No client-supplied text/chunks are accepted.
-- Source reads, hash, rate check and replacement commit (or roll back) together.
create function public.rebuild_memory_index(p_actor uuid,p_vault uuid,p_memory uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb; full_text text; notes text; bytes bigint; fingerprint text;
  previous heiro_security.memory_index_state%rowtype; counter heiro_security.index_rate%rowtype;
  minute_now timestamptz:=date_trunc('minute',now()); day_now date:=(now() at time zone 'UTC')::date;
  chunks integer;
begin
  if p_actor is null or not exists(select 1 from auth.users where id=p_actor
    and deleted_at is null and (banned_until is null or banned_until<now())) then
    raise exception 'INDEX_ACCESS_DENIED' using errcode='42501';
  end if;
  -- Serialize by actor and source; ordinary writers use the memory row lock too.
  perform pg_advisory_xact_lock(hashtextextended('index:'||p_actor::text,0));
  select to_jsonb(x) into m from public.memories x
    where x.id=p_memory and x.vault_id=p_vault for update;
  if m is null then raise exception 'INDEX_ACCESS_DENIED' using errcode='42501'; end if;
  select coalesce(sum(char_length(coalesce(transcript,''))+char_length(coalesce(title,''))+80),0)
    into bytes from public.memory_voice_notes where memory_id=p_memory and vault_id=p_vault;
  if bytes>180000 then raise exception 'INDEX_TEXT_LIMIT' using errcode='22001'; end if;
  select string_agg('Voice note ('||coalesce(nullif(title,''),'Voice note')||'):'||E'\n'||transcript,E'\n' order by created_at,id)
    into notes from public.memory_voice_notes where memory_id=p_memory and vault_id=p_vault
      and nullif(btrim(transcript),'') is not null;
  full_text:=concat_ws(E'\n',
    'Title: '||nullif(m->>'prompt_text',''),'Memory: '||nullif(m->>'body',''),
    'When: '||nullif(m->>'memory_date_label',''),'People: '||nullif(m->>'people',''),
    'Location: '||nullif(m->>'location',''),'Mood: '||nullif(m->>'mood',''),notes);
  if char_length(full_text)>256000 then raise exception 'INDEX_TEXT_LIMIT' using errcode='22001'; end if;
  fingerprint:=md5(full_text);
  select * into previous from heiro_security.memory_index_state where memory_id=p_memory;
  if found and previous.source_hash=fingerprint
    and previous.chunk_count=(select count(*) from public.memory_chunks where memory_id=p_memory and vault_id=p_vault) then
    return jsonb_build_object('ok',true,'unchanged',true,'chunk_count',previous.chunk_count);
  end if;
  insert into heiro_security.index_rate values(p_actor,minute_now,0,day_now,0) on conflict do nothing;
  select * into counter from heiro_security.index_rate where user_id=p_actor for update;
  if counter.minute<>minute_now then counter.minute_count:=0; end if;
  if counter.day<>day_now then counter.day_count:=0; end if;
  if counter.minute_count>=120 or counter.day_count>=1000 then
    raise exception 'INDEX_RATE_LIMIT' using errcode='P0001';
  end if;
  update heiro_security.index_rate set minute=minute_now,minute_count=counter.minute_count+1,
    day=day_now,day_count=counter.day_count+1 where user_id=p_actor;
  delete from public.memory_chunks where memory_id=p_memory and vault_id=p_vault;
  insert into public.memory_chunks(vault_id,memory_id,chunk_index,chunk_text)
    select p_vault,p_memory,i-1,substr(full_text,1+(i-1)*900,900)
    from generate_series(1,ceil(char_length(full_text)/900.0)::integer) i;
  get diagnostics chunks=row_count;
  insert into heiro_security.memory_index_state values(p_memory,fingerprint,chunks)
    on conflict(memory_id) do update set source_hash=excluded.source_hash,chunk_count=excluded.chunk_count;
  return jsonb_build_object('ok',true,'unchanged',false,'chunk_count',chunks);
end; $$;
revoke all on function public.rebuild_memory_index(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.rebuild_memory_index(uuid,uuid,uuid) to service_role;
