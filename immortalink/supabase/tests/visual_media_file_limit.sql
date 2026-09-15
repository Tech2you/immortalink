-- Exercise the deployed trigger as an uploader, not as postgres. Never touch
-- real storage objects: the probe and all grants disappear on rollback.
begin;
create temporary table media_limit_probe(bucket_id text, metadata jsonb);
create trigger probe before insert on media_limit_probe
for each row execute function public.enforce_visual_media_file_limit();
grant insert, select on media_limit_probe to authenticated;
set local role authenticated;

do $$
declare bucket text;
begin
  foreach bucket in array array['vault_photos', 'memory_photos', 'legacy_vault_photos', 'legacy_memory_photos'] loop
    insert into media_limit_probe values
      (bucket, '{"mimetype":"image/jpeg","size":12582912}'),
      (bucket, '{"mimetype":"video/mp4","size":52428800}');
    begin
      insert into media_limit_probe values (bucket, '{"mimetype":"image/jpeg","size":12582913}');
      raise exception 'Oversized photo accepted';
    exception when sqlstate '22023' then null;
    end;
    begin
      insert into media_limit_probe values (bucket, '{"mimetype":"video/mp4","size":52428801}');
      raise exception 'Oversized video accepted';
    exception when sqlstate '22023' then null;
    end;
  end loop;
  if (select count(*) from media_limit_probe) <> 8 then
    raise exception 'Expected eight accepted boundary files';
  end if;
end $$;
rollback;
