import {readFile} from 'node:fs/promises';
const migration=await readFile(new URL('../../migrations/20261106090245_media_backup_launch.sql',import.meta.url),'utf8');
const id='00000000-0000-4000-8000-000000000001';
export async function setup(db){await db.exec(`create role anon;create role authenticated;create role service_role;
 create schema storage;create table storage.objects(id uuid primary key,bucket_id text,name text,version text,updated_at timestamptz,metadata jsonb,archived_at timestamptz,is_delete_marker boolean);
 create schema heiro_business;create function heiro_business.require_owner() returns uuid language plpgsql as $$begin raise exception 'BUSINESS_ACCESS_DENIED';end$$;
 create schema net;create table net.requests(id bigint generated always as identity,url text,headers jsonb,body jsonb,timeout integer);
 create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer) returns bigint language sql as $$insert into net.requests(url,headers,body,timeout) values($1,$2,$3,$4) returning id$$;`);
 await db.exec(migration);await db.query("insert into storage.objects values($1,'memory_photos','generated/photo.jpg','v1',now(),'{\"size\":100}',null,false)",[id]);}
