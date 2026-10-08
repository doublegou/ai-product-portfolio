begin;
do $$
declare s public.transit_sources; run_id uuid; old_token uuid; payload jsonb; before_seen timestamptz;
begin
 insert into public.transit_sources(id,name,base_url,collector,config) values('transit-transaction-test','test','https://transit-test.example.com/','transit','{}') returning * into s;
 select * into s from public.claim_transit_sources(1,s.id);
 if s.lease_token is null then raise exception 'missing lease'; end if;
 if exists(select 1 from public.claim_transit_sources(1,s.id)) then raise exception 'double claim'; end if;
 insert into public.transit_crawl_runs(source_id) values(s.id) returning id into run_id;
 payload:=jsonb_build_object('id',s.id,'name','test','prices','[{"id":"test-model","inputPrice":1}]'::jsonb);
 perform public.complete_transit_crawl(s.id,s.lease_token,run_id,payload);
 select last_seen_at into before_seen from public.transit_snapshots where source_id=s.id;
 if not exists(select 1 from public.transit_snapshots where source_id=s.id and expires_at between now()+interval '44 minutes' and now()+interval '46 minutes') then raise exception 'expiry incorrect'; end if;
 select * into s from public.claim_transit_sources(1,s.id);old_token:=s.lease_token;
 insert into public.transit_crawl_runs(source_id) values(s.id) returning id into run_id;
 perform public.complete_transit_crawl(s.id,s.lease_token,run_id,null,'test failure');
 if not exists(select 1 from public.transit_snapshots where source_id=s.id and last_seen_at=before_seen and data=payload) then raise exception 'failure changed snapshot'; end if;
 if not exists(select 1 from public.transit_sources where id=s.id and next_crawl_at>now()+interval '29 minutes' and failure_count=1) then raise exception 'failure backoff missing'; end if;
 select * into s from public.claim_transit_sources(1,s.id);
 insert into public.transit_crawl_runs(source_id) values(s.id) returning id into run_id;
 begin perform public.complete_transit_crawl(s.id,old_token,run_id,payload);raise exception 'stale lease accepted';exception when others then if sqlerrm='stale lease accepted' then raise;end if;end;
 begin perform public.complete_transit_crawl(s.id,s.lease_token,run_id,jsonb_set(payload,'{prices}','[]'));raise exception 'empty snapshot accepted';exception when others then if sqlerrm='empty snapshot accepted' then raise;end if;end;
 update public.transit_sources set enabled=false where id=s.id;
 if public.transit_page(2,0)::text like '%transit-transaction-test%' then raise exception 'paused source exposed';end if;
 if has_table_privilege('anon','public.transit_snapshots','select') or has_table_privilege('authenticated','public.transit_sources','update') then raise exception 'table privileges leaked';end if;
 if has_function_privilege('anon','public.claim_transit_sources(integer,text)','execute') or has_function_privilege('anon','public.transit_page(integer,integer)','execute') then raise exception 'function privileges leaked';end if;
end $$;
rollback;
select 'transit transaction invariants passed; fixtures rolled back' as result;
