(() => {
  'use strict';
  const stage = document.querySelector('.deck-stage');
  const slides = Array.from(document.querySelectorAll('.deck-stage > .slide'));
  if (!stage || !slides.length) return;
  const levels = slides.map(slide => [...new Set(Array.from(slide.querySelectorAll('[data-step]'), el => Number(el.dataset.step)).filter(n => Number.isInteger(n) && n > 0))].sort((a,b) => a-b));
  const params = new URLSearchParams(location.search);
  const safeInt = (value, fallback) => value !== null && /^\d+$/.test(value) && Number.isSafeInteger(Number(value)) ? Number(value) : fallback;
  const navigation = createSlideState(levels.map(list => list.length), safeInt(params.get('slide'), 1)-1, safeInt(params.get('step'), 0));
  const help = document.querySelector('.deck-help');
  const counter = document.querySelector('.deck-counter');
  const button = name => document.querySelector(`[data-action="${name}"]`);
  const jump=document.querySelector('#slide-jump');
  if(jump)slides.forEach((slide,i)=>{const o=document.createElement('option');o.value=String(i);o.textContent=`${i+1} · ${slide.getAttribute('aria-label')||slide.querySelector('h1')?.textContent||'页面'}`;jump.appendChild(o)});
  const render = () => {
    const {page, step} = navigation.read();
    slides.forEach((slide, i) => {
      const active = i === page;
      slide.classList.toggle('is-active', active);
      slide.inert = !active;
      slide.setAttribute('aria-hidden', String(!active));
      const threshold = step === 0 ? 0 : levels[page][step-1];
      slide.querySelectorAll('[data-step]').forEach(el => {
        const value = Number(el.dataset.step);
        const visible = active && value <= threshold;
        el.classList.toggle('is-revealed', visible);
        el.setAttribute('aria-hidden', String(!visible));
      });
    });
    if(jump)jump.value=String(page);
    stage.dataset.page = String(page+1);
    stage.dataset.step = String(step);
    stage.dataset.steps = String(levels[page].length);
    if (counter) counter.textContent = `${page+1}/${slides.length} · ${step}/${levels[page].length}`;
    if (button('prev')) button('prev').disabled = page === 0 && step === 0;
    if (button('next')) button('next').disabled = page === slides.length-1 && step === levels[page].length;
  };
  if(jump)jump.addEventListener('change',()=>{const p=Number(jump.value);while(navigation.read().page<p)navigation.send('page-next');while(navigation.read().page>p)navigation.send('page-prev');navigation.send('replay');render();jump.blur()});
  const dispatch = action => { navigation.send(action); render(); };
  const next = () => dispatch('next');
  const prev = () => dispatch('prev');
  const flip = delta => dispatch(delta > 0 ? 'page-next' : 'page-prev');
  const replay = () => dispatch('replay');
  const full = async () => {
    try { if (document.fullscreenElement) await document.exitFullscreen(); else await document.documentElement.requestFullscreen(); }
    catch { if (help) { help.hidden=false; help.textContent='此浏览器未开启全屏，请使用浏览器窗口的全屏按钮。'; } }
  };
  const actions = { next, prev, replay, clean: () => document.body.classList.toggle('is-clean'), help: () => { if (help) help.hidden=!help.hidden; }, full };
  document.querySelectorAll('[data-action]').forEach(el => el.addEventListener('click', () => actions[el.dataset.action]?.()));
  document.addEventListener('keydown', event => {
    if (event.altKey || event.ctrlKey || event.metaKey || event.repeat || event.target.closest('input,textarea,select,[contenteditable="true"]')) return;
    const key=event.key.toLowerCase();
    const keys={ ' ':next, arrowright:next, arrowleft:prev, pagedown:()=>flip(1), pageup:()=>flip(-1), r:replay, f:full, v:actions.clean, '?':actions.help, escape:()=>{ document.body.classList.remove('is-clean'); document.body.classList.add('controls-open'); if(help)help.hidden=true; } };
    if (keys[key]) { event.preventDefault(); keys[key](); }
  });
  // Use a single pointer path for mouse and touch so one gesture advances once.
  const interactive = target => !!target.closest('button,a,select,input,textarea,[contenteditable="true"],.deck-control-zone,.deck-controls,.deck-help');
  let start = null;
  document.addEventListener('pointerdown', event => {
    if (!event.isPrimary || event.button !== 0 || interactive(event.target)) { start=null; return; }
    start={x:event.clientX,y:event.clientY,id:event.pointerId};
  });
  document.addEventListener('pointerup', event => {
    if (!start || event.pointerId !== start.id) return;
    const dx=event.clientX-start.x, dy=event.clientY-start.y;
    start=null;
    if (interactive(event.target)) return;
    if (Math.abs(dx)>50 && Math.abs(dx)>Math.abs(dy)*1.5) { dx<0 ? next() : prev(); return; }
    if (Math.hypot(dx,dy)<12) next();
  });
  document.addEventListener('pointercancel',()=>{start=null;});
  const scale = () => {
    const width=stage.offsetWidth, height=stage.offsetHeight;
    if (!width || !height) return;
    const factor=Math.min(innerWidth/width,innerHeight/height);
    stage.style.transform=`translate(${(innerWidth-width*factor)/2}px, ${(innerHeight-height*factor)/2}px) scale(${factor})`;
  };
  addEventListener('resize',scale);
  if (params.get('clean') === '1') document.body.classList.add('is-clean');
  scale(); render();
})();
