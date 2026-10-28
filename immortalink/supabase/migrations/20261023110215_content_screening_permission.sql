-- Permission foundation only. No queue, upload trigger or provider is enabled.
create table content_safety.screening_permissions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  policy_version text not null,
  allowed boolean not null,
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now()
);
alter table content_safety.screening_permissions enable row level security;
revoke all on content_safety.screening_permissions
  from public, anon, authenticated, service_role;

create function public.get_content_screening_permission()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_policy constant text := 'openai-safety-text-photo-2026-10-23';
  v_result jsonb;
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  select pg_catalog.jsonb_build_object(
    'policy_version', v_policy,
    'allowed', p.allowed and p.policy_version = v_policy,
    'revision', p.revision::text
  ) into v_result
  from content_safety.screening_permissions p where p.user_id = v_user;
  return coalesce(v_result, pg_catalog.jsonb_build_object(
    'policy_version', v_policy, 'allowed', false, 'revision', '0'
  ));
end;
$$;

create function public.set_content_screening_permission(
  p_allowed boolean, p_policy_version text, p_expected_user_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_policy constant text := 'openai-safety-text-photo-2026-10-23';
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  -- A dialog opened before an account switch must not grant the new account.
  if p_expected_user_id is distinct from v_user then
    raise exception 'Account changed; reopen permission settings' using errcode = '42501';
  end if;
  if p_allowed is null then
    raise exception 'Permission choice required' using errcode = '22023';
  end if;
  if p_allowed and p_policy_version is distinct from v_policy then
    raise exception 'Screening disclosure changed' using errcode = '22023';
  end if;
  -- Withdrawal must work even from an older disclosure. Every choice advances
  -- the epoch so a later opt-in cannot revive work claimed before withdrawal.
  insert into content_safety.screening_permissions as p
    (user_id, policy_version, allowed)
  values (v_user, v_policy, p_allowed)
  on conflict (user_id) do update set
    policy_version = excluded.policy_version,
    allowed = excluded.allowed,
    revision = p.revision + 1,
    updated_at = pg_catalog.now();
  return public.get_content_screening_permission();
end;
$$;

-- Future claim/finish RPCs must also validate content revision, recipient access,
-- deletion, restrictions and work budget. This predicate alone cannot publish.
create function content_safety.screening_permission_matches(
  p_user_id uuid, p_revision bigint
)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from content_safety.screening_permissions p
    where p.user_id = p_user_id and p.allowed
      and p.policy_version = 'openai-safety-text-photo-2026-10-23'
      and p.revision = p_revision
  );
$$;

revoke all on function public.get_content_screening_permission()
  from public, anon, authenticated, service_role;
revoke all on function public.set_content_screening_permission(boolean, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function content_safety.screening_permission_matches(uuid, bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.get_content_screening_permission()
  to authenticated;
grant execute on function public.set_content_screening_permission(boolean, text, uuid)
  to authenticated;
grant usage on schema content_safety to service_role;
grant execute on function content_safety.screening_permission_matches(uuid, bigint)
  to service_role;
