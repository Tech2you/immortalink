import { readFile } from 'node:fs/promises';
import { publicationFixture, dispatched } from './publication_fixture.mjs';
import { finish, rpc } from './screening_fixture.mjs';
import { memory } from './retirement_fixture.mjs';

export const reviewSql = await readFile(new URL('../../migrations/20261024162740_content_screening_human_review.sql',import.meta.url),'utf8');
export const statusSql = await readFile(new URL('../../migrations/20261024120503_content_screening_client_status.sql',import.meta.url),'utf8');
export async function reviewFixture(db,options) {
  db=await publicationFixture(db,options); await db.exec(statusSql); await db.exec(reviewSql); return db;
}
export async function flagged(db,kind='memory',target=memory) {
  const job=await dispatched(db,kind,target); await finish(db,job,'review');
  return (await db.query('select id from content_safety.screening_reviews where target_id=$1 order by created_at desc',[target])).rows[0].id;
}
export const queue=(db,state='active')=>rpc(db,'screening_review_queue($1)',[state]);
export const preview=(db,id,reviewer='QA',media=null,revision=null)=>rpc(db,'preview_screening_review($1,$2,$3,$4)',[id,reviewer,media,revision]);
export const decide=(db,id,revision,action='approve',reviewer='QA',notes='Disposable QA review')=>
  rpc(db,'decide_screening_review($1,$2,$3,$4,$5)',[id,action,reviewer,notes,revision]);
export const ack=(db,id,media,revision,reviewer='QA')=>rpc(db,'ack_screening_review_media($1,$2,$3,$4)',[id,reviewer,media,revision]);
export async function inspected(db,id,reviewer='QA') {
  const data=await preview(db,id,reviewer);
  for(const item of data.media){await preview(db,id,reviewer,item.id,data.revision);await ack(db,id,item.id,data.revision,reviewer);}
  return data;
}
