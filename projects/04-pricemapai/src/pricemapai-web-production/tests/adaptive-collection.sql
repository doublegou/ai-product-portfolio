begin;
do $$
declare s public.sources; r uuid; payload jsonb; other_id uuid;
begin
 if public.source_stock_interval(now()-interval '15 days',3,false)<>10080
  or public.source_stock_interval(now()-interval '15 days',3,true)<>1440
  or public.source_stock_interval(now()-interval '4 days',3,false)<>1440
  or public.source_stock_interval(now()-interval '2 days',1,false)<>360 then raise exception 'stock observation intervals incorrect'; end if;
 insert into public.sources(name,base_url,collector,created_at) values('adaptive-test','https://adaptive-test.invalid','json',now()-interval '10 days') returning * into s;
 payload:='[{"external_id":"1","raw_title":"ChatGPT Plus","platform":"ChatGPT","plan":"Plus","delivery":"代充","duration_days":30,"comparison_key":"adaptive-isolated-key","review_required":false,"price":100,"currency":"CNY","stock_status":"unknown","purchase_url":"https://adaptive-test.invalid/1"}]';
 select * into s from public.claim_sources(1,s.id);
 insert into public.crawl_runs(source_id) values(s.id) returning id into r;
 perform public.complete_crawl(s.id,s.lease_token,r,payload,true);
 if not exists(select 1 from public.sources where id=s.id and availability_state='unknown' and interval_minutes=180) then raise exception 'unknown inventory/first insertion incorrectly prioritized'; end if;
 if not exists(select 1 from public.crawl_runs where id=r and changed_offer_count=0 and new_offer_count=1) then raise exception 'new offers counted as changes'; end if;
 select * into s from public.claim_sources(1,s.id);
 insert into public.crawl_runs(source_id) values(s.id) returning id into r;
 perform public.complete_crawl(s.id,s.lease_token,r,'[]',false);
 if exists(select 1 from public.sources where id=s.id and availability_state='out_of_stock') then raise exception 'partial empty snapshot inferred empty shop'; end if;
 select * into s from public.claim_sources(1,s.id);
 insert into public.crawl_runs(source_id) values(s.id) returning id into r;
 perform public.complete_crawl(s.id,s.lease_token,r,'[]',true);
 if not exists(select 1 from public.sources where id=s.id and availability_state='out_of_stock' and out_of_stock_confirmations=1) then raise exception 'complete empty snapshot not observed'; end if;
 select * into s from public.claim_sources(1,s.id);
 insert into public.crawl_runs(source_id) values(s.id) returning id into r;
 perform public.complete_crawl(s.id,s.lease_token,r,'[]',false,'timeout');
 if not exists(select 1 from public.sources where id=s.id and out_of_stock_confirmations=1) then raise exception 'failure extended stock observation'; end if;
 select * into s from public.claim_sources(1,s.id);
 insert into public.crawl_runs(source_id) values(s.id) returning id into r;
 payload:=jsonb_set(payload,'{0,stock_status}','"in_stock"');
 perform public.complete_crawl(s.id,s.lease_token,r,payload,true);
 if not exists(select 1 from public.sources where id=s.id and availability_state='available' and out_of_stock_since is null and out_of_stock_confirmations=0) then raise exception 'restock not reset'; end if;
 -- Isolate density from the ingestion fixtures above.
 delete from public.crawl_runs where source_id=s.id;
 insert into public.crawl_runs(source_id,status,checked_offer_count,changed_offer_count) values(s.id,'success',100,1);
 perform public.refresh_source_collection_policy(s.id);
 if exists(select 1 from public.sources where id=s.id and collection_tier='changing') then raise exception 'single small change promoted entire merchant'; end if;
 insert into public.crawl_runs(source_id,status,checked_offer_count,changed_offer_count) values(s.id,'success',100,50),(s.id,'success',100,50);
 perform public.refresh_source_collection_policy(s.id);
 if not exists(select 1 from public.sources where id=s.id and interval_minutes=15 and collection_tier='changing') then raise exception 'repeated dense changes not prioritized'; end if;
 delete from public.crawl_runs where source_id=s.id;
 if exists(select 1 from public.collection_value_signals() where source_id=s.id and low_price_guard) then raise exception 'single merchant treated as competitive minimum'; end if;
 insert into public.sources(name,base_url,collector) values('competitor-test','https://competitor-test.invalid','json') returning id into other_id;
 insert into public.offers(source_id,external_id,raw_title,platform,plan,delivery,duration_days,comparison_key,review_required,price,currency,stock_status,purchase_url,expires_at)
 values(other_id,'1','Plus','ChatGPT','Plus','代充',30,'adaptive-isolated-key',false,200,'USD','in_stock','https://competitor-test.invalid/1',now()+interval '1 hour');
 if exists(select 1 from public.collection_value_signals() where source_id=s.id and low_price_guard) then raise exception 'cross currency comparison'; end if;
 update public.offers set currency='CNY' where source_id=other_id;
 perform public.refresh_source_collection_policy(s.id);
 if not exists(select 1 from public.sources where id=s.id and interval_minutes=60 and collection_tier='lowprice_guard') then raise exception 'low-price guard missing'; end if;
 update public.offers set duration_days=90 where source_id=other_id;
 if exists(select 1 from public.collection_value_signals() where source_id=s.id and low_price_guard) then raise exception 'cross duration comparison'; end if;
 update public.offers set stock_status='out_of_stock' where source_id=s.id;
 update public.sources set availability_state='out_of_stock',out_of_stock_since=now()-interval '15 days',out_of_stock_confirmations=3 where id=s.id;
 perform public.refresh_source_collection_policy(s.id);
 select * into s from public.claim_sources(1,s.id);
 insert into public.crawl_runs(source_id) values(s.id) returning id into r;
 perform public.complete_crawl(s.id,s.lease_token,r,'[]',false,'timeout');
 if not exists(select 1 from public.sources where id=s.id and interval_minutes=10080 and next_crawl_at>=now()+interval '7 days' and out_of_stock_confirmations=3) then raise exception 'weekly stock observation accelerated after error'; end if;
 update public.sources set adaptive_enabled=false,interval_minutes=77 where id=s.id;
 perform public.refresh_source_collection_policy(s.id);
 if not exists(select 1 from public.sources where id=s.id and interval_minutes=77) then raise exception 'manual interval overridden'; end if;
 if has_function_privilege('anon','public.collection_value_signals()','execute') then raise exception 'private collection signals leaked'; end if;
end $$;
rollback;
select 'adaptive collection invariants passed; fixtures rolled back' result;
