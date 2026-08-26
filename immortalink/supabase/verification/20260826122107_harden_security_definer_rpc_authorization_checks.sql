-- Verification for 20260826121840_harden_security_definer_rpc_authorization.sql
--
-- Intended usage:
--   psql "$DATABASE_URL" -f supabase/verification/20260826121840_harden_security_definer_rpc_authorization_checks.sql
--
-- Rollback-safe. Creates temporary rows, raises on failure, then rolls back.

begin;

do $$
declare
  v_user_id uuid := gen_random_uuid();
  v_other_user_id uuid := gen_random_uuid();
  v_family_id uuid := gen_random_uuid();
  v_other_family_id uuid := gen_random_uuid();
  v_vault_id uuid := gen_random_uuid();
  v_other_vault_id uuid := gen_random_uuid();
  v_legacy_id uuid := gen_random_uuid();
  v_created_id uuid;
  v_rejected boolean;
begin
  insert into auth.users (
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at
  )
  values
    (v_user_id, 'authenticated', 'authenticated', 'security-rpc-user@example.test', 'test', now(), now(), now()),
    (v_other_user_id, 'authenticated', 'authenticated', 'security-rpc-other@example.test', 'test', now(), now(), now());

  insert into public.family_groups (id, name, created_by, created_at)
  values
    (v_family_id, 'Security RPC Family', v_user_id, now()),
    (v_other_family_id, 'Security RPC Other Family', v_other_user_id, now());

  insert into public.family_members (family_id, user_id, role, joined_at, is_primary)
  values
    (v_family_id, v_user_id, 'owner', now(), true),
    (v_other_family_id, v_other_user_id, 'owner', now(), true);

  insert into public.vaults (id, owner_id, family_id, name, display_name, created_at)
  values
    (v_vault_id, v_user_id, v_family_id, 'Security RPC User', 'Security RPC User', now()),
    (v_other_vault_id, v_other_user_id, v_other_family_id, 'Security RPC Other', 'Security RPC Other', now());

  insert into public.legacy_family_members (
    id,
    family_id,
    name,
    display_name,
    created_by,
    created_at
  )
  values (
    v_legacy_id,
    v_family_id,
    'Existing Legacy Anchor',
    'Existing Legacy Anchor',
    v_user_id,
    now()
  );

  perform set_config('request.jwt.claim.sub', v_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  if not public.is_family_member(v_family_id, v_user_id) then
    raise exception 'Expected caller to pass own family membership check';
  end if;

  if public.is_family_member(v_other_family_id, v_other_user_id) then
    raise exception 'Expected direct membership probe for another user to fail';
  end if;

  v_rejected := false;
  begin
    perform public.get_family_layout(v_vault_id);
  exception
    when insufficient_privilege then
      v_rejected := true;
    when others then
      v_rejected := true;
  end;

  if not v_rejected then
    raise exception 'Expected authenticated get_family_layout execution to be blocked';
  end if;

  select public.create_legacy_relative(
    v_family_id,
    'vault',
    v_vault_id,
    'child',
    'Valid Legacy Child',
    null,
    null,
    null,
    null
  ) into v_created_id;

  if v_created_id is null then
    raise exception 'Expected valid same-family legacy relative creation to succeed';
  end if;

  v_rejected := false;
  begin
    perform public.create_legacy_relative(
      v_family_id,
      'vault',
      v_other_vault_id,
      'child',
      'Invalid Cross Family Child',
      null,
      null,
      null,
      null
    );
  exception
    when insufficient_privilege then
      v_rejected := true;
    when others then
      v_rejected := true;
  end;

  if not v_rejected then
    raise exception 'Expected cross-family vault anchor to be rejected';
  end if;

  select public.create_legacy_relative(
    v_family_id,
    'legacy',
    v_legacy_id,
    'child',
    'Valid Legacy Grandchild',
    null,
    null,
    null,
    null
  ) into v_created_id;

  if v_created_id is null then
    raise exception 'Expected valid same-family legacy anchor to succeed';
  end if;

  reset role;
end;
$$;

rollback;
