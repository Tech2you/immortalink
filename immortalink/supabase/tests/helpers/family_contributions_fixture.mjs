import {readFile} from 'node:fs/promises';
const {PGlite}=await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
export const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
export const a=id(1), b=id(2), c=id(3), f=id(101), g=id(102);
const read=n=>readFile(new URL(`../../migrations/${n}.sql`,import.meta.url),'utf8');
export const bucketMigration=(await read('20261030150145_pooled_family_storage_contributions'))+'\n'+(await read('20261030152751_preserve_beta_access_with_contributions'));
export async function fixture({db=new PGlite(),bucket=true}={}) {
 await db.exec(`create role anon;create role authenticated;create role service_role;
 create schema auth;create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 grant usage on schema auth to authenticated,service_role;
 create table family_groups(id uuid primary key);
 create table family_members(family_id uuid,user_id uuid,role text);
 create table vaults(id uuid default gen_random_uuid(),owner_id uuid,display_name text,name text,created_at timestamptz default now());
 create table family_entitlements(id uuid primary key default gen_random_uuid(),family_id uuid references family_groups on delete cascade,plan text,status text,provider text,
  provider_customer_id text,provider_entitlement_id text,provider_subscription_id text,billing_owner_user_id uuid references auth.users on delete set null,
  current_period_start timestamptz,current_period_end timestamptz,cancel_at_period_end boolean default false,
  apple_original_transaction_id text,apple_product_id text,apple_environment text,created_at timestamptz default now(),updated_at timestamptz default now());
 create unique index family_entitlements_family_unique on family_entitlements(family_id);
 create unique index family_entitlements_apple_original_tx_unique on family_entitlements(apple_original_transaction_id) where apple_original_transaction_id is not null;
 alter table family_entitlements enable row level security;
 create policy member_read on family_entitlements for select to authenticated using(exists(select 1 from family_members where family_id=family_entitlements.family_id and user_id=auth.uid()));
 grant select on family_entitlements,family_members to authenticated;
 create table apple_subscription_events(id uuid default gen_random_uuid(),family_id uuid,user_id uuid,event_source text,apple_environment text,
  apple_product_id text,apple_original_transaction_id text,apple_transaction_id text,notification_type text,entitlement_status text,raw_payload jsonb,created_at timestamptz default now());
 insert into auth.users values('${a}'),('${b}'),('${c}');
 insert into family_groups values('${f}'),('${g}');
 insert into family_members values('${f}','${a}','owner'),('${f}','${b}','member'),('${g}','${c}','owner');
 insert into vaults(owner_id,name) values('${a}','Alex'),('${b}','Blair'),('${c}','Casey');`);
 for(const n of ['20260928212954_family_sponsorship','20260928223253_sponsorship_checkout_lifecycle','20260929111512_returning_family_sponsor','20261001221344_apple_environment_isolation','20261011205859_acknowledge_retired_apple_history','20261028120027_verified_apple_repurchase_after_expiry']) await db.exec(await read(n));
 if(bucket)await db.exec(bucketMigration);
 return db;
}
export const asUser=(db,user)=>db.query("select set_config('test.uid',$1,false)",[user]);
export async function begin(db,user=a,family=f,legacy=false) {
 await asUser(db,user);
 return (await db.query(`select ${legacy?'begin_family_sponsorship':'begin_family_storage_contribution'}($1) r`,[family])).rows[0].r;
}
export function tx(user=a,chain=`chain-${user}`,extra={}) {
 return {bundleId:'com.everroots.app',originalTransactionId:chain,transactionId:`${chain}-first`,environment:'Sandbox',
  productId:'everroots.family.monthly',appAccountToken:user,transactionReason:'PURCHASE',purchaseDate:Date.now(),signedDate:Date.now(),expiresDate:Date.now()+86400000,...extra};
}
export async function apply(db,t,user=a,family=f,source='client_validation',notification=null) {
 return (await db.query('select apply_verified_family_subscription($1,$2,$3,$4,$5) r',[JSON.stringify(t),family,user,source,notification])).rows[0].r;
}
export const limits=async(db,family=f)=>(await db.query('select everroot_limits($1) r',[family])).rows[0].r;
export const GB=1073741824;
