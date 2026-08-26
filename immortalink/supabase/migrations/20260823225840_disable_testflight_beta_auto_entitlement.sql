-- Stop automatically granting the temporary TestFlight paid-family entitlement
-- to newly created families. Existing beta entitlements are intentionally
-- left untouched so active testers are not unexpectedly downgraded.

drop trigger if exists everroot_testflight_beta_family_entitlement_after_insert
  on public.family_groups;
