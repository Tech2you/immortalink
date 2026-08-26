-- Verification for 20260826105333_harden_family_invite_abuse_controls.sql
--
-- Intended usage:
--   psql "$DATABASE_URL" -f supabase/verification/20260826105333_harden_family_invite_abuse_controls_checks.sql
--
-- This script is rollback-safe. It creates temporary verification rows inside a
-- transaction, raises if a guard fails, then rolls back all data changes.

begin;

do $$
declare
  v_owner_id uuid := gen_random_uuid();
  v_member_id uuid := gen_random_uuid();
  v_non_member_id uuid := gen_random_uuid();
  v_joiner_id uuid := gen_random_uuid();
  v_pending_family_id uuid := gen_random_uuid();
  v_monthly_family_id uuid := gen_random_uuid();
  v_cooldown_family_id uuid := gen_random_uuid();
  v_duplicate_family_id uuid := gen_random_uuid();
  v_rls_family_id uuid := gen_random_uuid();
  v_invite_id uuid;
  v_i integer;
  v_user_id uuid;
  v_rejected boolean;
  v_detail text;
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
    (v_owner_id, 'authenticated', 'authenticated', 'invite-owner@example.test', 'test', now(), now(), now()),
    (v_member_id, 'authenticated', 'authenticated', 'invite-member@example.test', 'test', now(), now(), now()),
    (v_non_member_id, 'authenticated', 'authenticated', 'invite-non-member@example.test', 'test', now(), now(), now()),
    (v_joiner_id, 'authenticated', 'authenticated', 'invite-joiner@example.test', 'test', now(), now(), now());

  insert into public.family_groups (id, name, created_by, created_at)
  values
    (v_pending_family_id, 'Invite Pending Guard', v_owner_id, now()),
    (v_monthly_family_id, 'Invite Monthly Guard', v_owner_id, now()),
    (v_cooldown_family_id, 'Invite Cooldown Guard', v_owner_id, now()),
    (v_duplicate_family_id, 'Invite Duplicate Guard', v_owner_id, now()),
    (v_rls_family_id, 'Invite RLS Guard', v_owner_id, now());

  insert into public.family_members (family_id, user_id, role, joined_at, is_primary)
  values
    (v_pending_family_id, v_owner_id, 'owner', now(), false),
    (v_monthly_family_id, v_owner_id, 'owner', now(), false),
    (v_cooldown_family_id, v_owner_id, 'owner', now(), false),
    (v_duplicate_family_id, v_owner_id, 'owner', now(), false),
    (v_rls_family_id, v_member_id, 'member', now(), false);

  -- Pending free-family boundary: 10 active unused invites allowed; 11th rejected.
  for v_i in 1..10 loop
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
      'pending-invite-' || v_i || '@example.test',
      'test',
      now(),
      now(),
      now()
    );

    insert into public.family_invites (
      family_id,
      created_by,
      invite_code,
      expires_at
    )
    values (
      v_pending_family_id,
      v_user_id,
      'PEND' || lpad(v_i::text, 6, '0'),
      now() + interval '7 days'
    );
  end loop;

  v_rejected := false;
  begin
    insert into public.family_invites (
      family_id,
      created_by,
      invite_code,
      expires_at
    )
    values (
      v_pending_family_id,
      v_owner_id,
      'PEND000011',
      now() + interval '7 days'
    );
  exception
    when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      if coalesce(v_detail, '') <> 'ERR_EVERROOT_PENDING_INVITE_LIMIT' then
        raise exception 'Expected pending invite limit, got %', v_detail;
      end if;
      v_rejected := true;
  end;

  if not v_rejected then
    raise exception 'Expected 11th active pending invite to be rejected';
  end if;

  -- Monthly free-family boundary: 25 monthly creations allowed; 26th rejected.
  -- Mark each invite used so the pending cap does not mask the monthly cap.
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
      'monthly-invite-' || v_i || '@example.test',
      'test',
      now(),
      now(),
      now()
    );

    insert into public.family_invites (
      family_id,
      created_by,
      invite_code,
      expires_at,
      used_at,
      used_by
    )
    values (
      v_monthly_family_id,
      v_user_id,
      'MONTH' || lpad(v_i::text, 5, '0'),
      now() + interval '7 days',
      now(),
      v_joiner_id
    );
  end loop;

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
    'monthly-invite-26@example.test',
    'test',
    now(),
    now(),
    now()
  );

  v_rejected := false;
  begin
    insert into public.family_invites (
      family_id,
      created_by,
      invite_code,
      expires_at
    )
    values (
      v_monthly_family_id,
      v_user_id,
      'MONTH00026',
      now() + interval '7 days'
    );
  exception
    when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      if coalesce(v_detail, '') <> 'ERR_EVERROOT_INVITE_LIMIT' then
        raise exception 'Expected monthly invite limit, got %', v_detail;
      end if;
      v_rejected := true;
  end;

  if not v_rejected then
    raise exception 'Expected 26th monthly invite to be rejected';
  end if;

  -- Cooldown: same creator cannot create two invites in a family within 10 seconds.
  insert into public.family_invites (
    family_id,
    created_by,
    invite_code,
    expires_at
  )
  values (
    v_cooldown_family_id,
    v_owner_id,
    'COOLDOWN01',
    now() + interval '7 days'
  );

  v_rejected := false;
  begin
    insert into public.family_invites (
      family_id,
      created_by,
      invite_code,
      expires_at
    )
    values (
      v_cooldown_family_id,
      v_owner_id,
      'COOLDOWN02',
      now() + interval '7 days'
    );
  exception
    when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      if coalesce(v_detail, '') <> 'ERR_EVERROOT_INVITE_COOLDOWN' then
        raise exception 'Expected invite cooldown, got %', v_detail;
      end if;
      v_rejected := true;
  end;

  if not v_rejected then
    raise exception 'Expected cooldown invite to be rejected';
  end if;

  -- Repeat-recipient guard when optional recipient fields are supplied.
  insert into public.family_invites (
    family_id,
    created_by,
    invite_code,
    expires_at,
    recipient_email,
    recipient_phone
  )
  values (
    v_duplicate_family_id,
    v_owner_id,
    'DUP0000001',
    now() + interval '7 days',
    'Relative@Example.Test',
    '+1 (555) 010-1111'
  );

  v_rejected := false;
  begin
    insert into public.family_invites (
      family_id,
      created_by,
      invite_code,
      expires_at,
      recipient_email
    )
    values (
      v_duplicate_family_id,
      v_member_id,
      'DUP0000002',
      now() + interval '7 days',
      ' relative@example.test '
    );
  exception
    when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      if coalesce(v_detail, '') <> 'ERR_EVERROOT_DUPLICATE_INVITE_RECIPIENT' then
        raise exception 'Expected duplicate email invite recipient, got %', v_detail;
      end if;
      v_rejected := true;
  end;

  if not v_rejected then
    raise exception 'Expected duplicate email recipient invite to be rejected';
  end if;

  v_rejected := false;
  begin
    insert into public.family_invites (
      family_id,
      created_by,
      invite_code,
      expires_at,
      recipient_phone
    )
    values (
      v_duplicate_family_id,
      v_member_id,
      'DUP0000003',
      now() + interval '7 days',
      '15550101111'
    );
  exception
    when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      if coalesce(v_detail, '') <> 'ERR_EVERROOT_DUPLICATE_INVITE_RECIPIENT' then
        raise exception 'Expected duplicate phone invite recipient, got %', v_detail;
      end if;
      v_rejected := true;
  end;

  if not v_rejected then
    raise exception 'Expected duplicate phone recipient invite to be rejected';
  end if;

  -- RLS: anon cannot create invites.
  v_rejected := false;
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'anon', true);
    set local role anon;

    insert into public.family_invites (
      family_id,
      created_by,
      invite_code,
      expires_at
    )
    values (
      v_rls_family_id,
      v_owner_id,
      'ANON000001',
      now() + interval '7 days'
    );
  exception
    when others then
      v_rejected := true;
  end;

  reset role;

  if not v_rejected then
    raise exception 'Expected anon invite creation to be rejected';
  end if;

  -- RLS: authenticated non-member cannot create an invite for the family.
  v_rejected := false;
  begin
    perform set_config('request.jwt.claim.sub', v_non_member_id::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    set local role authenticated;

    insert into public.family_invites (
      family_id,
      created_by,
      invite_code,
      expires_at
    )
    values (
      v_rls_family_id,
      v_non_member_id,
      'NONMEM0001',
      now() + interval '7 days'
    );
  exception
    when others then
      v_rejected := true;
  end;

  reset role;

  if not v_rejected then
    raise exception 'Expected non-member invite creation to be rejected';
  end if;

  -- RLS: authenticated family member can still create a normal code-only invite.
  perform set_config('request.jwt.claim.sub', v_member_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  insert into public.family_invites (
    family_id,
    created_by,
    invite_code,
    expires_at
  )
  values (
    v_rls_family_id,
    v_member_id,
    'MEMBER0001',
    now() + interval '7 days'
  )
  returning id into v_invite_id;

  reset role;

  if v_invite_id is null then
    raise exception 'Expected family member invite creation to succeed';
  end if;
end;
$$;

rollback;
