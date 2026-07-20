alter table public.memories
  add column if not exists mood text;

comment on column public.memories.mood is
  'Optional feeling or emotional tone selected by the memory author.';
