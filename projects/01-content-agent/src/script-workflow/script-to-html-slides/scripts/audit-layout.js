// Read-only expression for a browser's supported evaluate API. Run after fonts
// and transitions settle, at each relevant visible state. Does not change pages.
(() => {
  const stage = document.querySelector('.deck-stage');
  const active = Array.from(document.querySelectorAll('.slide.is-active'));
  const errors = [], review = [];
  if (!stage || active.length !== 1) return {errors:['Expected one stage and one active slide'],review};
  const slide = active[0], bounds = stage.getBoundingClientRect();
  const label = el => el.id || el.getAttribute('data-qa-block') || (el.textContent || '').trim().slice(0,50) || el.tagName;
  const visible = el => {
    for (let node=el; node && node!==stage.parentElement; node=node.parentElement) {
      const style=getComputedStyle(node);
      if (style.display==='none' || style.visibility==='hidden' || Number(style.opacity)===0) return false;
    }
    const r=el.getBoundingClientRect(); return r.width>0 && r.height>0;
  };
  const outside = (r,b) => r.left < b.left-2 || r.top < b.top-2 || r.right > b.right+2 || r.bottom > b.bottom+2;
  const elements = Array.from(slide.querySelectorAll('h1,h2,h3,h4,p,li,img,svg,[data-qa-block],[data-qa-text]')).filter(visible);
  for (const el of elements) {
    const r=el.getBoundingClientRect();
    if (outside(r,bounds) && !el.hasAttribute('data-qa-bleed')) errors.push({kind:'outside-stage',element:label(el)});
    if (el.namespaceURI !== 'http://www.w3.org/2000/svg' && (el.scrollWidth>el.clientWidth+2 || el.scrollHeight>el.clientHeight+2)) review.push({kind:'element-overflow',element:label(el)});
    if (el.matches('h1,h2,h3,h4,p,li,[data-qa-text]')) {
      const range=document.createRange(); range.selectNodeContents(el);
      const rects=Array.from(range.getClientRects());
      if (rects.some(rect=>outside(rect,bounds))) errors.push({kind:'text-outside-stage',element:label(el)});
      for(let parent=el;parent&&parent!==stage;parent=parent.parentElement) {
        const style=getComputedStyle(parent);
        if (['hidden','clip','scroll','auto'].includes(style.overflowX) || ['hidden','clip','scroll','auto'].includes(style.overflowY)) {
          if (rects.some(rect=>outside(rect,parent.getBoundingClientRect()))) review.push({kind:'possible-text-clipping',element:label(el),ancestor:label(parent)});
        }
      }
    }
  }
  const blocks=Array.from(slide.querySelectorAll('[data-qa-block]')).filter(visible);
  for(let i=0;i<blocks.length;i++) for(let j=i+1;j<blocks.length;j++) {
    const a=blocks[i], b=blocks[j];
    if(a.contains(b)||b.contains(a)||a.hasAttribute('data-qa-overlap')||b.hasAttribute('data-qa-overlap')) continue;
    const x=a.getBoundingClientRect(), y=b.getBoundingClientRect();
    if(Math.min(x.right,y.right)-Math.max(x.left,y.left)>2 && Math.min(x.bottom,y.bottom)-Math.max(x.top,y.top)>2) review.push({kind:'block-overlap',elements:[label(a),label(b)]});
  }
  return {page:stage.dataset.page,step:stage.dataset.step,stage:{width:stage.offsetWidth,height:stage.offsetHeight,ratio:bounds.width/bounds.height},fontsReady:document.fonts.status==='loaded',errors,review,scope:'Active-state geometry only; review intentional overlap, glyphs, meaning and visual quality separately.'};
})()
