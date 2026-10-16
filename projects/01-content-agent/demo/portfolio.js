const dialog=document.getElementById('image-dialog');
let imageOpener;
function showImage(button){imageOpener=button;const image=document.getElementById('dialog-image');image.src=button.dataset.image;image.alt=button.dataset.caption;document.getElementById('image-caption').textContent=button.dataset.caption;dialog.showModal();}
document.querySelectorAll('[data-image]').forEach(button=>button.addEventListener('click',()=>showImage(button)));
document.getElementById('close-image').addEventListener('click',()=>dialog.close());
dialog.addEventListener('close',()=>imageOpener?.focus({preventScroll:true}));
dialog.addEventListener('click',e=>{if(e.target===dialog)dialog.close();});
const tabs=[...document.querySelectorAll('[data-tab]')];
function activate(tab){tabs.forEach(b=>{const selected=b===tab;b.setAttribute('aria-selected',String(selected));b.tabIndex=selected?0:-1;document.getElementById('panel-'+b.dataset.tab).hidden=!selected;});}
tabs.forEach((tab,i)=>{tab.addEventListener('click',()=>activate(tab));tab.addEventListener('keydown',e=>{let n;if(e.key==='ArrowRight')n=(i+1)%tabs.length;else if(e.key==='ArrowLeft')n=(i+tabs.length-1)%tabs.length;else if(e.key==='Home')n=0;else if(e.key==='End')n=tabs.length-1;else return;e.preventDefault();activate(tabs[n]);tabs[n].focus();});});
document.querySelectorAll('[data-ratio]').forEach(button=>button.addEventListener('click',()=>{document.querySelectorAll('[data-ratio]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));const src='script-workflow/2026-09-26-agentic-video/artifacts/post/005/'+button.dataset.ratio+'.png';const label=button.dataset.ratio.replace('-',':');document.getElementById('cover-image').src=src;document.getElementById('cover-image').alt='第 005 期 '+label+' 封面';const zoom=document.getElementById('cover-zoom');zoom.dataset.image=src;zoom.dataset.caption='第 005 期 · '+label+' 封面';}));
document.getElementById('play-deck').addEventListener('click',()=>{const frame=document.createElement('iframe');frame.src='script-workflow/2026-10-16-version-alignment/ppt/001.html';frame.title='第 005 期实际演示 · 点击或方向键播放';frame.allowFullscreen=true;document.getElementById('deck-stage').replaceChildren(frame);});
