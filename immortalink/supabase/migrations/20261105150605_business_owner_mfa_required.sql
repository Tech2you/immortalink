-- Business access only. Normal app sessions, family roles and app RLS stay unchanged.
create function heiro_business.require_owner_identity() returns uuid
language plpgsql stable security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_session text:=auth.jwt()->>'session_id';
begin
 if v_uid is null or not exists(select 1 from heiro_business.owners where user_id=v_uid)
   or not exists(select 1 from auth.users where id=v_uid and deleted_at is null
     and not coalesce(is_anonymous,false) and (banned_until is null or banned_until<now()))
   or not exists(select 1 from auth.sessions where id::text=v_session and user_id=v_uid
     and (not_after is null or not_after>now())) then
   raise exception 'BUSINESS_ACCESS_DENIED' using errcode='42501';
 end if;
 return v_uid;
end; $$;
revoke all on function heiro_business.require_owner_identity() from public,anon,authenticated;
create or replace function heiro_business.require_owner() returns uuid
language plpgsql stable security definer set search_path='' as $$
declare v_uid uuid:=heiro_business.require_owner_identity();
begin
 if not exists(select 1 from auth.mfa_factors where user_id=v_uid and status='verified')
   or coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
   raise exception 'BUSINESS_MFA_REQUIRED' using errcode='42501';
 end if;
 return v_uid;
end; $$;
-- This reveals only the authenticated owner's own enrollment status. It never
-- bypasses MFA for business totals, expenses, activity controls or other users.
create function public.business_access_status() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_uid uuid:=heiro_business.require_owner_identity();
begin
 return jsonb_build_object('has_factor',exists(select 1 from auth.mfa_factors where user_id=v_uid and status='verified'),
   'verified',coalesce(auth.jwt()->>'aal','aal1')='aal2');
end; $$;
revoke all on function public.business_access_status() from public,anon;
grant execute on function public.business_access_status() to authenticated;
