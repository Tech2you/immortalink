-- Pending relationship-tree invitations temporarily occupy one side of a
-- relationship until the invited account joins. The join RPC replaces the
-- invite endpoint with the new vault endpoint.

alter table public.family_relationships
  drop constraint if exists family_relationships_parent_type_check;

alter table public.family_relationships
  add constraint family_relationships_parent_type_check
  check (parent_type in ('vault', 'legacy', 'invite'));

alter table public.family_relationships
  drop constraint if exists family_relationships_child_type_check;

alter table public.family_relationships
  add constraint family_relationships_child_type_check
  check (child_type in ('vault', 'legacy', 'invite'));
