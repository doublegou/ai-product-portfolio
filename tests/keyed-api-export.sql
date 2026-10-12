begin;
do $$
declare old_row jsonb; new_row jsonb; held jsonb; patches jsonb; id text:=md5('model-a:group-1');
begin
 old_row:=public.snapshot_index_transit('{"source_id":"relay","data":{"prices":[{"id":"model-a:group-1","inputPrice":1,"publicMonitoring":{"rate":0.9,"updatedAt":"t1"}},{"id":"model-b:group-2","inputPrice":2}],"publicMonitoring":{"rate":0.8}}}');
 new_row:=public.snapshot_index_transit('{"source_id":"relay","data":{"prices":[{"id":"model-c:group-3","inputPrice":4},{"id":"model-a:group-1","inputPrice":3,"publicMonitoring":{"rate":1,"updatedAt":"t2"}}],"publicMonitoring":{"rate":1}}}');
 held:=public.snapshot_hold_monitoring(new_row,old_row,false);
 if held#>>array['data','prices',id,'inputPrice']<>'3' then raise exception 'Price was throttled with monitoring'; end if;
 if held#>>array['data','prices',id,'publicMonitoring','rate']<>'0.9' or held#>>'{data,publicMonitoring,rate}'<>'0.8' then raise exception 'Monitoring escaped two-hour cadence'; end if;
 if public.snapshot_hold_monitoring(new_row,old_row,true)<>new_row then raise exception 'Due monitoring did not refresh'; end if;
 patches:=public.snapshot_json_diff(old_row,held);
 if exists(select 1 from jsonb_array_elements(patches)p where p->'path'='["data","prices"]') then raise exception 'Model addition/removal replaced whole catalog'; end if;
 if not exists(select 1 from jsonb_array_elements(patches)p where p->'path'=to_jsonb(array['data','prices',id,'inputPrice'])) then raise exception 'Model price diff missing'; end if;
 begin
  perform public.snapshot_index_transit('{"data":{"prices":[{"id":"duplicate"},{"id":"duplicate"}]}}');
  raise exception 'Duplicate IDs were accepted';
 exception when others then
  if sqlerrm='Duplicate IDs were accepted' then raise; end if;
 end;
 if has_table_privilege('anon','public.snapshot_export_runs','select') or has_table_privilege('authenticated','public.snapshot_export_runs','select') then raise exception 'Private export telemetry exposed'; end if;
 if not exists(select 1 from pg_proc where oid='public.export_snapshot_batch(boolean)'::regprocedure and 'statement_timeout=30s'=any(proconfig)) then raise exception 'Timeout lost'; end if;
end $$;
rollback;
