import {readFile} from 'node:fs/promises';
import {reviewFixture} from './screening_review_fixture.mjs';
import {rpc} from './screening_fixture.mjs';
import {viewer} from './retirement_fixture.mjs';
export const deliverySql=await readFile(new URL('../../migrations/20261024170015_screening_delivery_outboxes.sql',import.meta.url),'utf8');
export async function deliveryFixture(db,enabled=true){
  db=await reviewFixture(db);
  await db.exec(await readFile(new URL('../../migrations/20260826185243_add_user_push_tokens.sql',import.meta.url),'utf8'));
  await db.exec(deliverySql);
  await db.query('insert into user_push_tokens(token,user_id,device_id) values($1,$2,$3)',['fixture-device-token',viewer,'fixture-device']);
  if(enabled)await db.exec('update content_safety.screening_delivery_config set enabled=true,email_enabled=true,push_enabled=true');
  return db;
}
export const issue=(db,channel='email')=>rpc(db,'issue_screening_delivery($1)',[channel]);
export const claimDelivery=(db,token)=>rpc(db,'claim_screening_delivery($1)',[token]);
export const authorize=(db,job)=>rpc(db,'authorize_screening_delivery($1,$2)',[job.id,job.lease]);
export const finishDelivery=(db,job,result='ACCEPTED',seconds=60)=>rpc(db,'finish_screening_delivery($1,$2,$3,$4)',[job.id,job.lease,result,seconds]);
export const health=db=>rpc(db,'screening_delivery_health()',[]);
export async function leased(db,channel='email'){return claimDelivery(db,await issue(db,channel));}
