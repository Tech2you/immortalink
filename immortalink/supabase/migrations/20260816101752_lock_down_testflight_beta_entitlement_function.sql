revoke all on function public.everroot_grant_testflight_beta_entitlement()
  from public;
revoke all on function public.everroot_grant_testflight_beta_entitlement()
  from anon;
revoke all on function public.everroot_grant_testflight_beta_entitlement()
  from authenticated;

comment on function public.everroot_grant_testflight_beta_entitlement() is
  'Temporary TestFlight beta helper approved by owner. Grants Ever Roots family entitlement to every newly created family until 2026-11-14. Remove before public App Store launch.';
