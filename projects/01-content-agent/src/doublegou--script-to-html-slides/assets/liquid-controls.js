(() => {
  const controls=document.querySelector('.deck-controls');
  if(!controls)return;
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  controls.addEventListener('pointermove',e=>{
    if(reduced.matches||e.pointerType!=='mouse')return;
    const r=controls.getBoundingClientRect();
    controls.style.setProperty('--glass-x',`${Math.max(0,Math.min(100,(e.clientX-r.left)/r.width*100))}%`);
    controls.style.setProperty('--glass-y',`${Math.max(0,Math.min(100,(e.clientY-r.top)/r.height*100))}%`);
  });
  controls.addEventListener('pointerleave',()=>{controls.style.removeProperty('--glass-x');controls.style.removeProperty('--glass-y')});
  document.addEventListener('pointermove',e=>{if(e.pointerType==='mouse')document.body.classList.remove('controls-open','keyboard-controls')});
  document.addEventListener('pointerleave',()=>document.body.classList.remove('controls-open','keyboard-controls'));
  document.addEventListener('keydown',e=>{if(e.key==='Tab')document.body.classList.add('keyboard-controls')});
})();
