alter table public.legacy_memories
  add column if not exists memory_date_label text,
  add column if not exists people text,
  add column if not exists location text,
  add column if not exists mood text;

comment on column public.legacy_memories.memory_date_label is
  'Optional human-readable time or era label for a legacy memory.';
comment on column public.legacy_memories.people is
  'Optional names or description of people present in a legacy memory.';
comment on column public.legacy_memories.location is
  'Optional place or setting for a legacy memory.';
comment on column public.legacy_memories.mood is
  'Optional observed emotional tone for a legacy memory.';
