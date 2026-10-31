import {readFile} from 'node:fs/promises';
import {fixture,asUser,a,f,g,begin,tx,apply} from './family_contributions_fixture.mjs';
export * from './family_contributions_fixture.mjs';
const read=n=>readFile(new URL(n,import.meta.url),'utf8');
export async function moveFixture(options){
 const db=await fixture(options);
 // Isolated quota-store prerequisites; the consumers themselves are unchanged
 // deployed definitions. Existing writable/burst policy has separate tests.
 await db.exec(`create table everroot_ai_usage_periods(scope_type text,scope_id uuid,period_start date,used_count integer check(used_count>=0),unique(scope_type,scope_id,period_start));
 create table everroot_transcription_usage_periods(scope_type text,scope_id uuid,period_start date,used_seconds integer check(used_seconds>=0),unique(scope_type,scope_id,period_start));
 create function everroot_period_start(p_at timestamptz default now()) returns date language sql stable as $$ select date_trunc('month',p_at)::date $$;
 create function everroot_limit_int(p_family uuid,p_metric text) returns integer language sql as $$select (everroot_limits(p_family)->>p_metric)::integer$$;
 create function everroot_assert_family_writable(uuid) returns void language plpgsql as $$begin return;end$$;
 create function everroot_assert_usage_burst(text,integer) returns void language plpgsql as $$begin return;end$$;
 create function everroot_quota_error(p_code text,p_message text) returns void language plpgsql as $$begin raise exception '%',p_code;end$$;`);
 await db.exec(await read('./contribution_move_quota_snapshot.sql'));
 await db.exec(await read('../../migrations/20261030192334_confirmed_family_contribution_moves.sql'));
 await db.exec(await read('../../migrations/20261030220413_recover_previous_family_checkout.sql'));
 return db;
}
export async function paidMoveFixture(options){
 const db=await moveFixture(options);const reservation=await begin(db);const t=tx();await apply(db,t);await db.query('select release_family_sponsorship($1,$2)',[f,reservation.reservation_id]);
 await relocate(db,a,f,g);return {db,t};
}
export const relocate=async(db,user,from,to)=>{
 await db.query('delete from family_members where family_id=$1 and user_id=$2',[from,user]);
 await db.query("insert into family_members values($1,$2,'member')",[to,user]);
};
export const move=async(db,t,user=a,target=g,confirmation=null)=>(await db.query('select move_verified_apple_contribution($1,$2,$3,$4) r',[JSON.stringify(t),user,target,confirmation])).rows[0].r;
export async function used(db,family,ai=0,seconds=0){
 await db.query("insert into everroot_ai_usage_periods values('family',$1,everroot_period_start(),$2) on conflict(scope_type,scope_id,period_start) do update set used_count=excluded.used_count",[family,ai]);
 await db.query("insert into everroot_transcription_usage_periods values('family',$1,everroot_period_start(),$2) on conflict(scope_type,scope_id,period_start) do update set used_seconds=excluded.used_seconds",[family,seconds]);
}
export const usage=async(db,family)=>(await db.query("select coalesce((select used_count from everroot_ai_usage_periods where scope_id=$1 and period_start=everroot_period_start()),0)::int ai,coalesce((select used_seconds from everroot_transcription_usage_periods where scope_id=$1 and period_start=everroot_period_start()),0)::int seconds",[family])).rows[0];
