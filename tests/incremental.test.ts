import test from 'node:test';
import assert from 'node:assert/strict';
import {mergeBatch, publicSnapshot, indexedTransit, type Batch} from '../snapshot/incremental.ts';
const batch: Batch={schema:1,revision:1,base_revision:0,full:true,generated_at:'2026-10-10T00:00:00Z',changes:[
 {key:'offers:a',value:{id:'a',_source_id:'shop',price:10}},
 {key:'freshness:shop',value:{last_seen_at:'2026-10-10T00:00:00Z',expires_at:'2026-10-10T00:45:00Z'}},
 {key:'transit:relay',value:{source_id:'relay',data:{prices:[{inputPrice:1},{inputPrice:2}]}}}
]};
test('schema 2 upgrades the old checkpoint locally and applies model add/remove/price changes',()=>{
 const row={source_id:'relay',data:{id:'relay',prices:[{id:'model-a:group-1',inputPrice:1},{id:'model-b:group-2',inputPrice:2}]}};
 const first=mergeBatch(null,{...batch,changes:[{key:'transit:relay',value:row}]});
 const indexed=indexedTransit(row);
 const keys=Object.keys(indexed.data.prices);
 const a=keys.find(k=>indexed.data.prices[k].id==='model-a:group-1')!;
 const b=keys.find(k=>indexed.data.prices[k].id==='model-b:group-2')!;
 const next=mergeBatch(first,{...batch,schema:2,revision:2,base_revision:1,full:false,changes:[
  {key:'transit:relay',patches:[{path:['data','prices',a,'inputPrice'],value:3},{path:['data','prices',b],remove:true},{path:['data','prices','newmodel'],value:{id:'model-c:group-3',inputPrice:4}}]}
 ]});
 assert.deepEqual((publicSnapshot(next).transit[0] as any).data.prices.map((p:any)=>[p.id,p.inputPrice]).sort(),[['model-a:group-1',3],['model-c:group-3',4]]);
 assert.equal(first.entities['transit:relay'].data.prices[0].inputPrice,1);
 assert.deepEqual(indexedTransit({...row,data:{...row.data,prices:[...row.data.prices].reverse()}}),indexed);
 assert.equal(mergeBatch(next,{...batch,schema:2,revision:2}),next);
 assert.throws(()=>indexedTransit({...row,data:{prices:[{id:'same'},{id:'same'}]}}),/Duplicate/);
 assert.throws(()=>indexedTransit({...row,data:{prices:[{}]}}),/Missing/);
});
test('delta patches nested prices, adds/removes records, and shares compact freshness',()=>{
 const first=mergeBatch(null,batch);
 const next=mergeBatch(first,{...batch,revision:2,base_revision:1,full:false,changes:[
  {key:'offers:a',patches:[{path:['price'],value:9}]},
  {key:'transit:relay',patches:[{path:['data','prices','1','inputPrice'],value:3}]},
  {key:'freshness:shop',patches:[{path:['last_seen_at'],value:'2026-10-10T00:10:00Z'}]},
  {key:'offers:b',value:{id:'b',_source_id:'shop',price:20,last_seen_at:'2026-10-09T00:00:00Z',expires_at:'2026-10-09T00:45:00Z'}}
 ]});
 assert.equal(first.entities['offers:a'].price,10);
 assert.equal(publicSnapshot(next).offers.length,2);
 assert.equal((publicSnapshot(next).offers[0] as any).last_seen_at,'2026-10-10T00:10:00Z');
 assert.equal((publicSnapshot(next).offers[1] as any).expires_at,'2026-10-09T00:45:00Z');
 assert.equal(next.entities['transit:relay'].data.prices[1].inputPrice,3);
 const removed=mergeBatch(next,{...batch,revision:3,base_revision:2,full:false,changes:[{key:'offers:a',remove:true}]});
 assert.equal(publicSnapshot(removed).offers.length,1);
});
test('retries are idempotent and missing revisions require full recovery',()=>{
 const state=mergeBatch(null,batch);
 assert.equal(mergeBatch(state,batch),state);
 assert.throws(()=>mergeBatch(state,{...batch,revision:3,base_revision:2,full:false}),/Full snapshot required/);
 assert.throws(()=>mergeBatch(null,{...batch,full:false}),/Full snapshot required/);
 assert.equal(mergeBatch(state,{...batch,revision:4,full:true,changes:[]}).entities['offers:a'],undefined);
 const empty=mergeBatch(state,{...batch,revision:2,base_revision:1,full:false,generated_at:'2026-10-10T01:00:00Z',changes:[]});
 assert.equal(empty.revision,2);assert.equal(empty.dirty_revision,1);assert.equal(empty.generated_at,state.generated_at);
});
test('unsafe/missing patch parents and invalid array changes leave previous checkpoint unchanged',()=>{
 const state=mergeBatch(null,batch);
 for(const path of [['__proto__','polluted'],['data','missing','x'],['data','prices','9'],['data','prices','0']]){
  assert.throws(()=>mergeBatch(state,{...batch,revision:2,base_revision:1,full:false,changes:[{key:'transit:relay',patches:[{path,remove:true}]}]}));
 }
 assert.equal(state.entities['transit:relay'].data.prices.length,2);
});
