import {useEffect,useState} from 'react';
import {loadTransit} from '../data/transit-client';
import type {TransitStation} from './apiTransit';
export function useTransit(enabled=true){
 const [stations,setStations]=useState<TransitStation[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState('');
 useEffect(()=>{
  if(!enabled)return;let active=true,busy=false,last=0;let controller:AbortController|undefined;
  async function refresh(){if(busy||Date.now()-last<60000||document.visibilityState==='hidden')return;busy=true;last=Date.now();controller=new AbortController();const timer=window.setTimeout(()=>controller?.abort(),90000);
   try{const data=await loadTransit(fetch,controller.signal);if(active){setStations(data);setError('');}}
   catch(e){if(active)setError(e instanceof Error?e.message:'API 报价读取失败');}
   finally{window.clearTimeout(timer);busy=false;if(active)setLoading(false);}
  }
  void refresh();const timer=window.setInterval(()=>void refresh(),300000);const focus=()=>void refresh();window.addEventListener('focus',focus);document.addEventListener('visibilitychange',focus);
  return()=>{active=false;controller?.abort();window.clearInterval(timer);window.removeEventListener('focus',focus);document.removeEventListener('visibilitychange',focus);};
 },[enabled]);
 return {stations,loading,error};
}
