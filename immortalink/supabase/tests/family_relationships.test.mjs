import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { setBytes } from './helpers/family_growth_fixture.mjs';
import { relationshipFixture, ownerVault } from './helpers/family_relationship_fixture.mjs';
import { authenticate, ownerA, ownerB, user, familyA, familyB, vault } from './helpers/single_family_fixture.mjs';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const anchor = {type:'vault',id:ownerVault};
const request = (relation='sibling', extra={}) => ({mode:'legacy',name:'Relative',anchor,relation,gap:0,
  shared_parents:[],partners:[],children:[],other_parent:null,...extra});
const create = async (db,r=request(),id=randomUUID()) =>
  (await db.query('select create_family_relative($1,$2,$3) result',[familyA,id,r])).rows[0].result;
const edges = async db => (await db.query('select * from family_relationships')).rows;
const rejects = (p,message) => assert.rejects(p,e=>e.message===message || e.detail===message);
async function run(fn) {
  const db=new PGlite();
  try {
    await relationshipFixture(db);
    await authenticate(db,ownerA);
    await fn(db);
  } finally { await db.close(); }
}
async function admin(db,fn) {
  await db.exec('reset role');
  try { return await fn(); } finally { await db.exec('set role authenticated'); }
}

test('sibling without recorded parents is a sibling, never a child; no UPDATE permission needed',()=>run(async db=>{
  const result=await create(db);
  assert.equal(result.type,'legacy');
  assert.deepEqual((await edges(db)).map(r=>[r.parent_id,r.child_id,r.relationship_kind]),[[ownerVault,result.id,'sibling']]);
  assert.equal((await db.query("update family_relationships set relationship_kind='parent_child' returning id")).rows.length,0);
}));

test('half-sibling uses only selected parent, full sibling uses both, unknown parentage remains separate',()=>run(async db=>{
  const a=await create(db,request('parent',{name:'Parent A'}));
  const b=await create(db,request('parent',{name:'Parent B'}));
  const half=await create(db,request('sibling',{name:'Half',shared_parents:[a]}));
  const full=await create(db,request('sibling',{name:'Full',shared_parents:[a,b]}));
  const unknown=await create(db,request('sibling',{name:'Unknown'}));
  const rows=await edges(db);
  assert.deepEqual(rows.filter(r=>r.child_id===half.id).map(r=>r.parent_id),[a.id]);
  assert.deepEqual(rows.filter(r=>r.child_id===full.id).map(r=>r.parent_id).sort(),[a.id,b.id].sort());
  assert.equal(rows.find(r=>r.child_id===unknown.id).relationship_kind,'sibling');
}));

test('invited child and other-parent placeholder save together, then survive invite acceptance',()=>run(async db=>{
  const child=await create(db,request('child',{mode:'invite',other_parent:{type:'placeholder'}}));
  assert.equal((await edges(db)).filter(r=>r.child_id===child.id).length,2);
  await db.query("select set_config('test.uid',$1,false)",[user]);
  await db.query('select join_family_by_relationship_invite($1)',[child.invite_code]);
  const rows=await edges(db);
  assert.equal(rows.filter(r=>r.child_id===vault && r.child_type==='vault').length,2);
  assert.equal(rows.some(r=>r.child_type==='invite'),false);
}));

test('expired invite fails without changing relationships',()=>run(async db=>{
  const child=await create(db,request('child',{mode:'invite'}));
  await admin(db,()=>db.query("update family_invites set expires_at=now()-interval '1 day' where id=$1",[child.id]));
  await db.query("select set_config('test.uid',$1,false)",[user]);
  await assert.rejects(db.query('select join_family_by_relationship_invite($1)',[child.invite_code]),/expired/);
  await admin(db,async()=>assert.equal((await edges(db))[0].child_id,child.id));
}));

test('a parent cannot accept their child own child-invite; failed join preserves invite and membership',()=>run(async db=>{
  await admin(db,()=>db.exec(`insert into family_members(family_id,user_id,role) values('${familyA}','${user}','member');
    insert into family_relationships(family_id,parent_type,parent_id,child_type,child_id,relationship_kind)
      values('${familyA}','vault','${vault}','vault','${ownerVault}','parent_child')`));
  const child=await create(db,request('child',{mode:'invite'}));
  await db.query("select set_config('test.uid',$1,false)",[user]);
  await rejects(db.query('select join_family_by_relationship_invite($1)',[child.invite_code]),'RELATIONSHIP_ANCESTRY_CYCLE');
  await admin(db,async()=>{
    assert.equal((await db.query('select count(*)::int n from family_invites where id=$1',[child.id])).rows[0].n,1);
    assert.equal((await edges(db)).length,2);
  });
}));

test('direct inserts reject cross-family endpoints, unknown kinds, self links and ancestry cycles',()=>run(async db=>{
  const parent=await create(db,request('parent'));
  const insert=(first,second,kind='parent_child')=>db.query(`insert into family_relationships
    (family_id,parent_type,parent_id,child_type,child_id,relationship_kind) values($1,$2,$3,$4,$5,$6)`,
    [familyA,first.type,first.id,second.type,second.id,kind]);
  await rejects(insert(anchor,parent),'RELATIONSHIP_ANCESTRY_CYCLE');
  await rejects(insert(anchor,anchor),'RELATIONSHIP_SELF_LINK');
  await rejects(insert(anchor,parent,'unknown'),'INVALID_RELATIONSHIP_KIND');
  await rejects(insert(anchor,{type:'vault',id:vault}),'RELATIONSHIP_PERSON_UNAVAILABLE');
}));

test('parent partners and selected children are explicit, not inferred',()=>run(async db=>{
  const child=await create(db,request('child',{name:'Child'}));
  const spouse=await create(db,request('spouse',{name:'Partner'}));
  assert.equal((await edges(db)).some(r=>r.parent_id===spouse.id && r.child_id===child.id),false);
  const coParent=await create(db,request('spouse',{name:'Co-parent',children:[child,child]}));
  assert.equal((await edges(db)).filter(r=>r.parent_id===coParent.id && r.child_id===child.id).length,1);
}));

test('grandparent/great-grandchild gaps retain the right direction and every generation',()=>run(async db=>{
  const grandparent=await create(db,request('parent',{gap:1,name:'Grandparent'}));
  const descendant=await create(db,request('child',{gap:2,name:'Great grandchild'}));
  const rows=await edges(db);
  let id=grandparent.id;
  for(let i=0;i<2;i++) id=rows.find(r=>r.parent_id===id).child_id;
  assert.equal(id,ownerVault);
  id=ownerVault;
  for(let i=0;i<3;i++) id=rows.find(r=>r.parent_id===id).child_id;
  assert.equal(id,descendant.id);
}));

test('legacy capacity failure rolls back all placeholders and the operation receipt',()=>run(async db=>{
  await admin(db,()=>db.exec(`insert into legacy_family_members(family_id,name)
    select '${familyA}','Existing' from generate_series(1,7)`));
  await rejects(create(db,request('parent',{gap:1})),'ERR_EVERROOT_LEGACY_LIMIT');
  await admin(db,async()=>{
    assert.equal((await db.query('select count(*)::int n from legacy_family_members')).rows[0].n,7);
    assert.equal((await db.query('select count(*)::int n from family_access.relationship_requests')).rows[0].n,0);
    assert.equal((await edges(db)).length,0);
  });
}));

test('late other-parent error rolls back profile, about memory, links and invite usage',()=>run(async db=>{
  const invalid={type:'vault',id:vault};
  for(const mode of ['legacy','invite']) await rejects(create(db,request('child',{mode,about:'Test bio',other_parent:invalid})),'RELATIONSHIP_PERSON_UNAVAILABLE');
  await admin(db,async()=>{
    for(const t of ['family_relationships','legacy_family_members','legacy_memories','family_invites','family_access.invite_rate_events'])
      assert.equal((await db.query(`select count(*)::int n from ${t}`)).rows[0].n,0,t);
  });
}));

test('retry returns the exact saved result without duplicates, changed payload is rejected',()=>run(async db=>{
  const id=randomUUID(), r=request('sibling',{about:'Kept once'});
  const first=await create(db,r,id);
  assert.deepEqual(await create(db,r,id),first);
  await rejects(create(db,{...r,name:'Different'},id),'RELATIONSHIP_RETRY_CHANGED');
  await admin(db,async()=>{
    assert.equal((await edges(db)).length,1);
    assert.equal((await db.query('select count(*)::int n from legacy_memories')).rows[0].n,1);
  });
}));

test('full storage, invite cooldown, one-family policy and outsider denial still apply',()=>run(async db=>{
  await admin(db,()=>setBytes(db,524288000));
  for(const mode of ['legacy','invite']) await rejects(create(db,request('sibling',{mode})),'ERR_EVERROOT_STORAGE_LIMIT');
  await admin(db,()=>setBytes(db,0));
  const invite=await create(db,request('sibling',{mode:'invite'}));
  await rejects(create(db,request('child',{mode:'invite',gap:1})),'ERR_EVERROOT_INVITE_COOLDOWN');
  await db.query("select set_config('test.uid',$1,false)",[ownerB]);
  await assert.rejects(create(db),e=>e.code==='42501');
  await rejects(db.query('select join_family_by_relationship_invite($1)',[invite.invite_code]),'FAMILY_MEMBERSHIP_LIMIT');
  await assert.rejects(db.query('select * from family_access.relationship_requests'),e=>e.code==='42501');
}));

test('multi-row ancestry cycles roll back the entire statement',()=>run(async db=>{
  await admin(db,async()=>{
    await db.query('insert into family_members(family_id,user_id,role) values($1,$2,$3)',[familyA,user,'member']);
    await rejects(db.query(`insert into family_relationships
      (family_id,parent_type,parent_id,child_type,child_id,relationship_kind) values
      ($1,'vault',$2,'vault',$3,'parent_child'),($1,'vault',$3,'vault',$2,'parent_child')`,
      [familyA,ownerVault,vault]),'RELATIONSHIP_ANCESTRY_CYCLE');
    assert.equal((await edges(db)).length,0);
  });
}));

test('anonymous users and direct calls to private helpers remain denied',()=>run(async db=>{
  const permissions=await admin(db,async()=>(await db.query(`select
    has_function_privilege('anon','public.create_family_relative(uuid,uuid,jsonb)','execute') anonymous,
    has_function_privilege('authenticated','family_access.add_relationship(uuid,jsonb,jsonb,text)','execute') helper,
    has_table_privilege('authenticated','family_access.relationship_requests','select') ledger`)).rows[0]);
  assert.deepEqual(permissions,{anonymous:false,helper:false,ledger:false});
  await assert.rejects(db.query('select family_access.add_relationship($1,$2,$3,$4)',
    [familyA,anchor,anchor,'sibling']),e=>e.code==='42501');
}));
