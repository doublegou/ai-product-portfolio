// Synthetic geometry tests only: no browser, font engine or rendering is used.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const code=fs.readFileSync(path.join(__dirname,'audit-layout.js'),'utf8');

function fixture(specs) {
  function element(spec={}) {
    const attrs=spec.attrs||{};
    const rect={left:spec.x||0,top:spec.y||0,width:spec.w||100,height:spec.h||50};
    rect.right=rect.left+rect.width;rect.bottom=rect.top+rect.height;
    const node={
      id:spec.id||'',tagName:spec.tag||'DIV',textContent:spec.text||'',dataset:{},parentElement:null,
      namespaceURI:'http://www.w3.org/1999/xhtml',style:{display:'block',visibility:'visible',opacity:'1',overflowX:'visible',overflowY:'visible',...spec.style},
      clientWidth:rect.width,clientHeight:rect.height,scrollWidth:spec.scrollWidth||rect.width,scrollHeight:rect.height,
      getBoundingClientRect:()=>rect,getAttribute:key=>attrs[key]??null,hasAttribute:key=>key in attrs,
      matches:()=>['H1','P','LI'].includes(spec.tag)||'data-qa-text' in attrs,
      contains(other){for(let p=other.parentElement;p;p=p.parentElement)if(p===node)return true;return false;},
      rects:spec.rects||[rect]
    };return node;
  }
  const viewport=element({w:1920,h:1080}),stage=element({w:1920,h:1080}),slide=element({w:1920,h:1080});
  stage.parentElement=viewport;stage.offsetWidth=1920;stage.offsetHeight=1080;stage.dataset={page:'1',step:'1'};slide.parentElement=stage;
  const nodes=specs.map(element);nodes.forEach(node=>node.parentElement=slide);
  slide.querySelectorAll=selector=>selector==='[data-qa-block]'?nodes.filter(node=>node.hasAttribute('data-qa-block')):nodes;
  const document={querySelector:()=>stage,querySelectorAll:()=>[slide],fonts:{status:'loaded'},createRange:()=>{let selected;return {selectNodeContents:node=>selected=node,getClientRects:()=>selected.rects};}};
  return JSON.parse(JSON.stringify(vm.runInNewContext(code,{document,getComputedStyle:node=>node.style})));
}
test('separated visible blocks yield no geometry defects',()=>{
  const report=fixture([{id:'title',tag:'H1',x:100,y:100,w:1200,h:100},{id:'a',x:100,y:300,w:600,h:450,attrs:{'data-qa-block':'a'}},{id:'b',x:900,y:300,w:600,h:450,attrs:{'data-qa-block':'b'}}]);
  assert.deepEqual(report.errors,[]);assert.deepEqual(report.review,[]);
});
test('outside text, marked-block overlap and clipped text are detected',()=>{
  const report=fixture([{id:'title',tag:'H1',x:1850,y:100,w:500,h:100},{id:'a',x:100,y:400,w:500,h:250,attrs:{'data-qa-block':'a'}},{id:'b',x:350,y:450,w:500,h:250,attrs:{'data-qa-block':'b'}},{id:'clipped',tag:'P',x:100,y:850,w:200,h:70,scrollWidth:600,style:{overflowX:'hidden'},rects:[{left:100,top:850,right:700,bottom:920,width:600,height:70}]}]);
  assert.ok(report.errors.some(x=>x.kind==='text-outside-stage'));
  assert.ok(report.review.some(x=>x.kind==='block-overlap'));
  assert.ok(report.review.some(x=>x.kind==='possible-text-clipping'));
});
test('hidden elements and explicitly intentional overlap are not flagged',()=>{
  const report=fixture([{id:'hidden',tag:'P',x:2500,w:500,style:{visibility:'hidden'}},{id:'a',x:100,y:400,w:500,h:250,attrs:{'data-qa-block':'a','data-qa-overlap':''}},{id:'b',x:350,y:450,w:500,h:250,attrs:{'data-qa-block':'b'}}]);
  assert.deepEqual(report.errors,[]);assert.deepEqual(report.review,[]);
});
