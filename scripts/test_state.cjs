const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createSlideState} = require('../assets/state.js');

test('next reveals every group before entering the next page', () => {
  const state=createSlideState([3,2]);
  assert.equal(state.send('next').step,1);
  assert.equal(state.send('next').step,2);
  assert.deepEqual(state.send('next'),{page:0,step:3,steps:3,pages:2});
  assert.deepEqual(state.send('next'),{page:1,step:0,steps:2,pages:2});
});
test('previous from a page start restores the preceding completed page', () => {
  const state=createSlideState([3,2],1,0);
  assert.deepEqual(state.send('prev'),{page:0,step:3,steps:3,pages:2});
  assert.equal(state.send('prev').step,2);
});
test('first and last boundaries remain valid under rapid repeated input', () => {
  const state=createSlideState([0,3,0,5]);
  for(let n=0;n<100;n++) state.send('prev');
  assert.equal(state.read().page,0);
  for(let n=0;n<100;n++) state.send('next');
  assert.deepEqual(state.read(),{page:3,step:5,steps:5,pages:4});
  for(let n=0;n<100;n++) state.send('prev');
  assert.deepEqual(state.read(),{page:0,step:0,steps:0,pages:4});
});
test('direct page changes reset reveal progress; replay stays on the page', () => {
  const state=createSlideState([3,5],0,2);
  assert.equal(state.send('page-next').step,0);
  state.send('next'); state.send('next');
  assert.deepEqual(state.send('replay'),{page:1,step:0,steps:5,pages:2});
  assert.equal(state.send('page-prev').page,0);
});
test('invalid or oversized initial locations clamp predictably', () => {
  assert.deepEqual(createSlideState([2,4],999,999).read(),{page:1,step:4,steps:4,pages:2});
  assert.deepEqual(createSlideState([2,4],NaN,-7).read(),{page:0,step:0,steps:2,pages:2});
  assert.throws(()=>createSlideState([]));
  assert.throws(()=>createSlideState([1,-1]));
});
test('input arrays and returned snapshots cannot mutate the navigation state', () => {
  const counts=[1,2], state=createSlideState(counts);
  counts[0]=999;
  const view=state.read(); view.step=100;
  assert.equal(state.send('next').step,1);
  assert.equal(state.send('next').page,1);
});
