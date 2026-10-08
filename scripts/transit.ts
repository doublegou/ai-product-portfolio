import {readFileSync} from 'node:fs';
import {workerEnv,clientFor} from './shared';
import {validateTransitSource,collectTransit, type TransitSource} from '../worker/transit';
import {crawlTransit} from '../worker/transit-crawl';
const rows:TransitSource[]=JSON.parse(readFileSync('config/verified-transit-sources.json','utf8')).map((s:TransitSource)=>({...validateTransitSource(s),id:s.id}));
const action=process.argv[2],id=process.argv.find(a=>a.startsWith('--source='))?.slice(9);
try {
 if(action==='import'){
  if(!process.argv.includes('--write'))console.log(`已校验 ${rows.length} 家原站配置；添加 --write 导入。`);
  else {const client=clientFor(workerEnv());const {error}=await client.from('transit_sources').upsert(rows,{onConflict:'id',ignoreDuplicates:true});if(error)throw Error(error.message);console.log(`已导入缺少的来源，共 ${rows.length} 家；保留已有配置与暂停状态。`);}
 }else if(action==='collect'){
  if(process.argv.includes('--write'))console.log(JSON.stringify(await crawlTransit(workerEnv(),id),null,2));
  else {const source=rows.find(s=>s.id===id);if(!source)throw Error('试采集请指定 --source=来源ID');const s=await collectTransit(source);console.log(JSON.stringify({source:s.name,count:s.prices.length,prices:s.prices.slice(0,3)},null,2));}
 }else throw Error('用法: transit.ts import|collect [--source=来源ID] [--write]');
}catch(e){console.error(e instanceof Error?e.message:'执行失败');process.exitCode=1;}
