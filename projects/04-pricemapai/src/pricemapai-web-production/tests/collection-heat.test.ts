import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeHeatSource} from '../src/lib/collection-heat';
test('heat counts preserve overlapping session categories, strip unrelated data, and accept legacy reports',()=>{
 assert.deepEqual(normalizeHeatSource({id:'shop',clicks:3,purchase_clicks:3,shop_clicks:3,ip:'private'} as any),{id:'shop',clicks:3,purchase_clicks:3,shop_clicks:3});
 assert.deepEqual(normalizeHeatSource({id:'shop',clicks:2}),{id:'shop',clicks:2});
 for(const count of [-1,4,NaN,1.5])assert.throws(()=>normalizeHeatSource({id:'shop',clicks:3,purchase_clicks:count}));
});
