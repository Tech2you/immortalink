alter table public.memories
  add column if not exists memory_date_label text,
  add column if not exists people text,
  add column if not exists location text;

comment on column public.memories.memory_date_label is
  'Optional human description such as Summer 2019 or when I was 10.';
comment on column public.memories.people is
  'Optional names or description of people present in the memory.';
comment on column public.memories.location is
  'Optional place associated with the memory.';
