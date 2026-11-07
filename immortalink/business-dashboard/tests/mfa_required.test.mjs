import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
const migration=await readFile(new URL('../../supabase/migrations/20261105150605_business_owner_mfa_required.sql',import.meta.url),'utf8');
test('owner business data requires enrollment AND current MFA while enrollment reveals no business data',async()=>{
 const db=new PGlite();try{await db.exec(`create role anon;create role authenticated;create schema auth;create schema heiro_business;
 create table auth.users(id uuid,deleted_at timestamptz,is_anonymous boolean,banned_until timestamptz);
 create table auth.sessions(id uuid,user_id uuid,not_after timestamptz);create table auth.mfa_factors(user_id uuid,status text);
 create table heiro_business.owners(user_id uuid);
 create function auth.jwt() returns jsonb language sql as $$select current_setting('test.jwt')::jsonb$$;
 create function auth.uid() returns uuid language sql as $$select (auth.jwt()->>'sub')::uuid$$;
 insert into auth.users values('00000000-0000-4000-8000-000000000001',null,false,null);
 insert into auth.sessions values('00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001',null);
 insert into heiro_business.owners values('00000000-0000-4000-8000-000000000001');`);
 await db.exec(migration);
 const claims={sub:'00000000-0000-4000-8000-000000000001',session_id:'00000000-0000-4000-8000-000000000002',aal:'aal1'};
 const jwt=()=>db.query("select set_config('test.jwt',$1,false)",[JSON.stringify(claims)]);await jwt();
 assert.deepEqual((await db.query('select business_access_status() status')).rows[0].status,{has_factor:false,verified:false});
 await assert.rejects(db.query('select heiro_business.require_owner()'),/BUSINESS_MFA_REQUIRED/);
 claims.aal='aal2';await jwt();await assert.rejects(db.query('select heiro_business.require_owner()'),/BUSINESS_MFA_REQUIRED/);
 await db.query("insert into auth.mfa_factors values($1,'verified')",[claims.sub]);
 assert.equal((await db.query('select heiro_business.require_owner() id')).rows[0].id,claims.sub);
 claims.aal='aal1';await jwt();await assert.rejects(db.query('select heiro_business.require_owner()'),/BUSINESS_MFA_REQUIRED/);
 claims.user_metadata={is_owner:true};claims.sub=claims.session_id;await jwt();await assert.rejects(db.query('select business_access_status()'),/BUSINESS_ACCESS_DENIED/);
 await db.exec('set role anon');await assert.rejects(db.query('select business_access_status()'),/permission denied/);
 }finally{await db.close();}
});
