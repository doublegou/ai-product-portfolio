import { ChevronLeft, ChevronRight } from 'lucide-react';
import './Pagination.css';

function pageItems(page: number, total: number): (number | 'gap')[] {
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);
  const pages = new Set([1, total]);
  const start = page <= 3 ? 1 : page >= total - 2 ? total - 3 : page - 1;
  const end = page <= 3 ? 4 : page >= total - 2 ? total : page + 1;
  for (let i = start; i <= end; i++) pages.add(i);
  const result: (number | 'gap')[] = [];
  let previous = 0;
  for (const value of [...pages].sort((a, b) => a - b)) {
    if (value - previous === 2) result.push(previous + 1);
    else if (value - previous > 2) result.push('gap');
    result.push(value);
    previous = value;
  }
  return result;
}

export function Pagination({page,total,onChange,label='分页'}:{page:number;total:number;onChange:(page:number)=>void;label?:string}) {
  if (total <= 1) return null;
  return <div className="pagination page-pagination">
    <nav aria-label={label}>
      <button type="button" aria-label="上一页" disabled={page<=1} onClick={()=>onChange(page-1)}><ChevronLeft size={18}/></button>
      {pageItems(page,total).map((item,i)=>item==='gap'?<span className="page-gap" key={`gap-${i}`} aria-hidden="true">…</span>:<button type="button" key={item} className={item===page?'active':''} aria-label={`第 ${item} 页`} aria-current={item===page?'page':undefined} onClick={()=>onChange(item)}>{item}</button>)}
      <button type="button" aria-label="下一页" disabled={page>=total} onClick={()=>onChange(page+1)}><ChevronRight size={18}/></button>
    </nav>
    <span className="page-total">共 {total} 页</span>
  </div>;
}
