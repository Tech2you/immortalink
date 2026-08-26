-- EverRoot Life360 entitlement verification checks.
--
-- Run only against a local or disposable staging database after applying:
--   20260822212756_everroot_life360_entitlement_adjustment.sql
--
-- The script is wrapped in a transaction and rolls back at the end. It creates
-- disposable auth users, vaults, families, memberships, and invites to prove:
-- - free families can invite and grow to 8 real members;
-- - Ever Roots Family can grow to 20 real members;
-- - invite cooldown still works;
-- - monthly invite limits still work;
-- - join_family_by_relationship_invite consumes an invite and links a member;
-- - no test data persists after the script.

begin;

do $$
declare
  v_free_family_id uuid := gen_random_uuid();
  v_paid_family_id uuid := gen_random_uuid();
  v_cooldown_family_id uuid := gen_random_uuid();
  v_invite_limit_family_id uuid := gen_random_uuid();
  v_join_family_id uuid := gen_random_uuid();
  v_owner_id uuid := gen_random_uuid();
  v_joiner_id uuid := gen_random_uuid();
  v_owner_vault_id uuid := gen_random_uuid();
  v_joiner_vault_id uuid := gen_random_uuid();
  v_invite_id uuid;
  v_joined_family_id uuid;
  v_before_counts jsonb;
  v_after_counts jsonb;
  v_sqlstate text;
  v_message text;
  v_detail text;
  v_i integer;
  v_user_id uuid;
begin
  select jsonb_build_object(
    'auth_users', (select count(*) from auth.users),
    'family_groups', (select count(*) from public.family_groups),
    'family_members', (select count(*) from public.family_members),
    'family_invites', (select count(*) from public.family_invites),
    'family_entitlements', (select count(*) from public.family_entitlements),
    'invite_usage', (select count(*) from public.everroot_invite_usage_periods)
  ) into v_before_counts;

  if (public.everroot_limits(null)->>'real_members')::integer <> 8 then
    raise exception 'Expected free real_members limit to be 8';
  end if;

  if (public.everroot_limits(null)->>'invites_monthly')::integer <> 25 then
    raise exception 'Expected free invites_monthly limit to be 25';
  end if;

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
    (v_owner_id, 'authenticated', 'authenticated', 'life360-owner@example.test', 'test', now(), now(), now()),
    (v_joiner_id, 'authenticated', 'authenticated', 'life360-joiner@example.test', 'test', now(), now(), now());

  insert into public.family_groups (id, name, created_by, created_at)
  values
    (v_free_family_id, 'Life360 Free Boundary', v_owner_id, now()),
    (v_paid_family_id, 'Life360 Paid Boundary', v_owner_id, now()),
    (v_cooldown_family_id, 'Life360 Invite Cooldown', v_owner_id, now()),
    (v_invite_limit_family_id, 'Life360 Invite Limit', v_owner_id, now()),
    (v_join_family_id, 'Life360 Join Flow', v_owner_id, now());

  insert into public.family_entitlements (
    family_id,
    plan,
    status,
    provider,
    provider_subscription_id,
    billing_owner_user_id,
    current_period_start,
    current_period_end
  )
  values (
    v_paid_family_id,
    'everroot_family',
    'active',
    'local_verification',
    'local_verification_' || v_paid_family_id::text,
    v_owner_id,
    now(),
    now() + interval '1 month'
  );

  if (public.everroot_limits(v_paid_family_id)->>'real_members')::integer <> 20 then
    raise exception 'Expected paid real_members limit to be 20';
  end if;

  -- Free member boundary: 8 allowed, 9th rejected.
  for v_i in 1..8 loop
    v_user_id := gen_random_uuid();
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
    values (
      v_user_id,
      'authenticated',
      'authenticated',
      'life360-free-member-' || v_i || '@example.test',
      'test',
      now(),
      now(),
      now()
    );

    insert into public.family_members (
      family_id,
      user_id,
      role,
      joined_at,
      is_primary
    )
    values (
      v_free_family_id,
      v_user_id,
      case when v_i = 1 then 'owner' else 'member' end,
      now(),
      v_i = 1
    );
  end loop;

  begin
    v_user_id := gen_random_uuid();
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
    values (
      v_user_id,
      'authenticated',
      'authenticated',
      'life360-free-member-9@example.test',
      'test',
      now(),
      now(),
      now()
    );

    insert into public.family_members (
      family_id,
      user_id,
      role,
      joined_at,
      is_primary
    )
    values (v_free_family_id, v_user_id, 'member', now(), false);

    raise exception 'Expected 9th free member to be rejected';
  exception
    when others then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_message = message_text,
        v_detail = pg_exception_detail;
      if coalesce(v_detail, '') <> 'ERR_EVERROOT_MEMBER_LIMIT'
         and v_message not like '%8 real family accounts%' then
        raise exception 'Unexpected free member boundary error: [%] % / %',
          v_sqlstate,
          v_message,
          v_detail;
      end if;
  end;

  -- Paid member boundary: 20 allowed, 21st rejected.
  for v_i in 1..20 loop
    v_user_id := gen_random_uuid();
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
    values (
      v_user_id,
      'authenticated',
      'authenticated',
      'life360-paid-member-' || v_i || '@example.test',
      'test',
      now(),
      now(),
      now()
    );

    insert into public.family_members (
      family_id,
      user_id,
      role,
      joined_at,
      is_primary
    )
    values (
      v_paid_family_id,
      v_user_id,
      case when v_i = 1 then 'owner' else 'member' end,
      now(),
      v_i = 1
    );
  end loop;

  begin
    v_user_id := gen_random_uuid();
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
    values (
      v_user_id,
      'authenticated',
      'authenticated',
      'life360-paid-member-21@example.test',
      'test',
      now(),
      now(),
      now()
    );

    insert into public.family_members (
      family_id,
      user_id,
      role,
      joined_at,
      is_primary
    )
    values (v_paid_family_id, v_user_id, 'member', now(), false);

    raise exception 'Expected 21st paid member to be rejected';
  exception
    when others then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_message = message_text,
        v_detail = pg_exception_detail;
      if coalesce(v_detail, '') <> 'ERR_EVERROOT_MEMBER_LIMIT'
         and v_message not like '%20 real family accounts%' then
        raise exception 'Unexpected paid member boundary error: [%] % / %',
          v_sqlstate,
          v_message,
          v_detail;
      end if;
  end;

  -- Invite cooldown: same user cannot create two invites within 10 seconds.
  insert into public.family_members (
    family_id,
    user_id,
    role,
    joined_at,
    is_primary
  )
  values (v_cooldown_family_id, v_owner_id, 'owner', now(), false);

  insert into public.family_invites (
    family_id,
    created_by,
    invite_code,
    slot_key,
    expires_at,
    inviter_vault_id
  )
  values (
    v_cooldown_family_id,
    v_owner_id,
    'LIFE360CD1',
    null,
    now() + interval '7 days',
    null
  );

  begin
    insert into public.family_invites (
      family_id,
      created_by,
      invite_code,
      slot_key,
      expires_at,
      inviter_vault_id
    )
    values (
      v_cooldown_family_id,
      v_owner_id,
      'LIFE360CD2',
      null,
      now() + interval '7 days',
      null
    );

    raise exception 'Expected invite cooldown to reject second invite';
  exception
    when others then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_message = message_text,
        v_detail = pg_exception_detail;
      if coalesce(v_detail, '') <> 'ERR_EVERROOT_INVITE_COOLDOWN' then
        raise exception 'Unexpected invite cooldown error: [%] % / %',
          v_sqlstate,
          v_message,
          v_detail;
      end if;
  end;

  -- Free monthly invite boundary: 25 allowed, 26th rejected. Use distinct
  -- creators to avoid testing the 10-second cooldown again.
  for v_i in 1..25 loop
    v_user_id := gen_random_uuid();
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
    values (
      v_user_id,
      'authenticated',
      'authenticated',
      'life360-invite-creator-' || v_i || '@example.test',
      'test',
      now(),
      now(),
      now()
    );

    insert into public.family_invites (
      family_id,
      created_by,
      invite_code,
      slot_key,
      expires_at,
      inviter_vault_id
    )
    values (
      v_invite_limit_family_id,
      v_user_id,
      'LIFE36' || lpad(v_i::text, 4, '0'),
      null,
      now() + interval '7 days',
      null
    );
  end loop;

  begin
    v_user_id := gen_random_uuid();
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
    values (
      v_user_id,
      'authenticated',
      'authenticated',
      'life360-invite-creator-26@example.test',
      'test',
      now(),
      now(),
      now()
    );

    insert into public.family_invites (
      family_id,
      created_by,
      invite_code,
      slot_key,
      expires_at,
      inviter_vault_id
    )
    values (
      v_invite_limit_family_id,
      v_user_id,
      'LIFE360026',
      null,
      now() + interval '7 days',
      null
    );

    raise exception 'Expected 26th free monthly invite to be rejected';
  exception
    when others then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_message = message_text,
        v_detail = pg_exception_detail;
      if coalesce(v_detail, '') <> 'ERR_EVERROOT_INVITE_LIMIT' then
        raise exception 'Unexpected free invite boundary error: [%] % / %',
          v_sqlstate,
          v_message,
          v_detail;
      end if;
  end;

  -- Join flow uses a separate free family so the monthly invite boundary above
  -- cannot consume the invite allowance before join_family_by_relationship_invite.
  insert into public.family_members (
    family_id,
    user_id,
    role,
    joined_at,
    is_primary
  )
  values (v_join_family_id, v_owner_id, 'owner', now(), true);

  insert into public.vaults (id, owner_id, family_id, name, display_name, created_at)
  values
    (v_owner_vault_id, v_owner_id, v_join_family_id, 'Life360 Owner', 'Life360 Owner', now()),
    (v_joiner_vault_id, v_joiner_id, null, 'Life360 Joiner', 'Life360 Joiner', now());

  insert into public.family_invites (
    family_id,
    created_by,
    invite_code,
    slot_key,
    expires_at,
    inviter_vault_id
  )
  values (
    v_join_family_id,
    v_owner_id,
    'LIFE360JOIN',
    null,
    now() + interval '7 days',
    v_owner_vault_id
  )
  returning id into v_invite_id;

  perform set_config('request.jwt.claim.sub', v_joiner_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  select public.join_family_by_relationship_invite('LIFE360JOIN')
    into v_joined_family_id;

  reset role;

  if v_joined_family_id <> v_join_family_id then
    raise exception 'Join returned wrong family id: expected %, got %',
      v_join_family_id,
      v_joined_family_id;
  end if;

  if not exists (
    select 1
    from public.family_members
    where family_id = v_join_family_id
      and user_id = v_joiner_id
  ) then
    raise exception 'Join did not create family_members row for joiner';
  end if;

  if exists (
    select 1
    from public.family_invites
    where id = v_invite_id
  ) then
    raise exception 'Join did not consume/delete the invite row';
  end if;

  reset role;

  select jsonb_build_object(
    'auth_users', (select count(*) from auth.users),
    'family_groups', (select count(*) from public.family_groups),
    'family_members', (select count(*) from public.family_members),
    'family_invites', (select count(*) from public.family_invites),
    'family_entitlements', (select count(*) from public.family_entitlements),
    'invite_usage', (select count(*) from public.everroot_invite_usage_periods)
  ) into v_after_counts;

  raise notice 'Life360 entitlement checks passed. Before counts=%, after counts inside rollback transaction=%',
    v_before_counts,
    v_after_counts;
exception
  when others then
    reset role;
    raise;
end
$$;

rollback;
