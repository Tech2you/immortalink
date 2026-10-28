-- Local-only split preparation. No image blobs, Storage policies, scheduler,
-- client grants or publication changes. Existing screening remains disabled.
create table content_safety.screening_photo_tickets (
  id uuid not null unique default gen_random_uuid(),
  job_id uuid not null references content_safety.screening_jobs(id) on delete cascade,
  image_index integer not null check (image_index between 0 and 3),
  lease_token uuid not null,
  revision text not null check (revision ~ '^[0-9a-f]{64}$'),
  source_id uuid not null,
  expires_at timestamptz not null,
  state text not null default 'processing' check (state in ('processing','ready')),
  output_bytes integer,
  output_sha256 text,
  primary key(job_id,image_index),
  check ((state='ready' and output_bytes between 1 and 2097152
      and output_sha256 ~ '^[0-9a-f]{64}$' and output_bytes is not null and output_sha256 is not null)
    or (state='processing' and output_bytes is null and output_sha256 is null))
);
alter table content_safety.screening_photo_tickets enable row level security;
revoke all on content_safety.screening_photo_tickets from public,anon,authenticated,service_role;

-- Retain the tested budget/source implementation privately. Only the wrapper
-- below can authorize dispatch, after every expected photo has finished.
alter function public.prepare_content_screening(uuid,uuid,boolean) set schema content_safety;
revoke all on function content_safety.prepare_content_screening(uuid,uuid,boolean)
  from public,anon,authenticated,service_role;

create function public.prepare_content_screening(p_job uuid,p_lease uuid,p_authorize boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s jsonb; prepared jsonb; n integer;
begin
  if p_authorize is null then return jsonb_build_object('code','LEASE_UNAVAILABLE'); end if;
  -- The private call takes lifecycle -> controls -> job locks, reserves the
  -- whole attempt once and rechecks current consent/deletion/source state.
  s:=content_safety.prepare_content_screening(p_job,p_lease,false);
  if s->>'code'<>'READY' then return s; end if;
  n:=jsonb_array_length(s->'images');
  select coalesce(jsonb_agg(jsonb_build_object('ticket_id',t.id,'image_index',t.image_index,
    'bytes',t.output_bytes,'sha256',t.output_sha256) order by t.image_index),'[]') into prepared
    from content_safety.screening_photo_tickets t
    where t.job_id=p_job and t.lease_token=p_lease and t.revision=s->>'revision'
      and t.expires_at>clock_timestamp() and t.state='ready' and t.image_index<n
      and t.source_id=(s->'images'->t.image_index->>'id')::uuid;
  if not p_authorize then return s || jsonb_build_object('prepared_images',prepared); end if;
  if jsonb_array_length(prepared)<>n then return jsonb_build_object('code','PHOTOS_NOT_READY'); end if;
  return content_safety.prepare_content_screening(p_job,p_lease,true);
end;
$$;

create function public.claim_content_screening_photo(p_job uuid,p_lease uuid,p_index integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s jsonb; t content_safety.screening_photo_tickets; until_at timestamptz;
begin
  if p_index is null or p_index not between 0 and 3 then
    return jsonb_build_object('code','PHOTO_UNAVAILABLE');
  end if;
  s:=content_safety.prepare_content_screening(p_job,p_lease,false);
  if s->>'code'<>'READY' then return jsonb_build_object('code',s->>'code'); end if;
  if p_index>=jsonb_array_length(s->'images') then return jsonb_build_object('code','PHOTO_UNAVAILABLE'); end if;
  select lease_until into until_at from content_safety.screening_jobs where id=p_job;
  -- At most four metadata rows per parent; old tickets cannot be replayed after
  -- replacement. No image copies exist to orphan or clean up after a crash.
  delete from content_safety.screening_photo_tickets where job_id=p_job and lease_token<>p_lease;
  insert into content_safety.screening_photo_tickets(job_id,image_index,lease_token,revision,source_id,expires_at)
    values(p_job,p_index,p_lease,s->>'revision',(s->'images'->p_index->>'id')::uuid,until_at)
    on conflict(job_id,image_index) do nothing returning * into t;
  if not found then return jsonb_build_object('code','PHOTO_ALREADY_CLAIMED'); end if;
  return jsonb_build_object('code','PHOTO_CLAIMED','ticket_id',t.id,'revision',t.revision,
    'image_index',p_index,'processing_reserved',true,'image',s->'images'->p_index);
end;
$$;

create function public.finish_content_screening_photo(p_ticket uuid,p_bytes integer,p_sha256 text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t content_safety.screening_photo_tickets; s jsonb;
begin
  if p_bytes is null or p_bytes not between 1 and 2097152 or p_sha256 is null
    or p_sha256 !~ '^[0-9a-f]{64}$' then return jsonb_build_object('code','PHOTO_INVALID'); end if;
  perform content_safety.media_lifecycle_lock();
  select * into t from content_safety.screening_photo_tickets where id=p_ticket;
  if not found or t.state<>'processing' or t.expires_at<=clock_timestamp() then
    return jsonb_build_object('code','PHOTO_UNAVAILABLE');
  end if;
  s:=content_safety.prepare_content_screening(t.job_id,t.lease_token,false);
  if s->>'code'<>'READY' or s->>'revision' is distinct from t.revision
    or (s->'images'->t.image_index->>'id')::uuid is distinct from t.source_id then
    return jsonb_build_object('code','SOURCE_CHANGED');
  end if;
  update content_safety.screening_photo_tickets set state='ready',output_bytes=p_bytes,output_sha256=p_sha256
    where id=p_ticket and state='processing';
  if not found then return jsonb_build_object('code','PHOTO_UNAVAILABLE'); end if;
  return jsonb_build_object('code','PHOTO_READY','revision',t.revision);
end;
$$;

revoke all on function public.prepare_content_screening(uuid,uuid,boolean) from public,anon,authenticated,service_role;
revoke all on function public.claim_content_screening_photo(uuid,uuid,integer) from public,anon,authenticated,service_role;
revoke all on function public.finish_content_screening_photo(uuid,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.prepare_content_screening(uuid,uuid,boolean),
  public.claim_content_screening_photo(uuid,uuid,integer),public.finish_content_screening_photo(uuid,integer,text) to service_role;
