create table public.ai_processing_consents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  policy_version text not null,
  allowed boolean not null,
  updated_at timestamptz not null default now()
);
alter table public.ai_processing_consents enable row level security;
revoke all on public.ai_processing_consents from public, anon, authenticated;

create function public.has_ai_processing_consent()
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select exists(select 1 from public.ai_processing_consents
    where user_id=auth.uid() and allowed and policy_version='openai-2026-10-01');
$$;

create function public.set_ai_processing_consent(p_allowed boolean)
returns void language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_allowed is null then raise exception 'Consent choice required'; end if;
  insert into public.ai_processing_consents(user_id,policy_version,allowed)
    values(auth.uid(),'openai-2026-10-01',p_allowed)
  on conflict(user_id) do update set policy_version=excluded.policy_version,
    allowed=excluded.allowed,updated_at=now();
end;
$$;
revoke all on function public.has_ai_processing_consent() from public, anon;
revoke all on function public.set_ai_processing_consent(boolean) from public, anon;
grant execute on function public.has_ai_processing_consent() to authenticated;
grant execute on function public.set_ai_processing_consent(boolean) to authenticated;
