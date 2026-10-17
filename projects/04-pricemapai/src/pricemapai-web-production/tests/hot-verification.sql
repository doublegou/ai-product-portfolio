begin;
do $$
declare s public.sources; manual_id uuid; untouched_id uuid; quote_id uuid; job jsonb; other_job jsonb; payload jsonb; original_seen timestamptz;
begin
 -- Isolate the bounded selection without changing live rows outside this rollback.
 update public.sources set adaptive_enabled=false;
 insert into public.sources(name,base_url,collector,interval_minutes,last_success_at,next_crawl_at)
 values('hot-test','https://hot-test.invalid','json',180,now()-interval '1 hour',now()+interval '2 hours') returning * into s;
 insert into public.sources(name,base_url,collector,adaptive_enabled) values('hot-manual-test','https://hot-manual-test.invalid','json',false) returning id into manual_id;
 insert into public.offers(source_id,external_id,raw_title,platform,plan,delivery,duration_days,comparison_key,review_required,price,currency,stock_status,purchase_url,expires_at)
 values(s.id,'target','ChatGPT Plus 代充 1个月','ChatGPT','Plus','代充',30,'hot-test',true,100,'CNY','in_stock','https://hot-test.invalid/target',now()+interval '1 hour') returning id into quote_id;
 insert into public.offers(source_id,external_id,raw_title,platform,plan,delivery,duration_days,comparison_key,review_required,price,currency,stock_status,purchase_url,expires_at)
 values(s.id,'untouched','Claude Pro','Claude','Pro','代充',30,'hot-other',false,100,'CNY','in_stock','https://hot-test.invalid/other',now()+interval '1 hour') returning id,last_seen_at into untouched_id,original_seen;
 insert into public.offers(source_id,external_id,raw_title,platform,plan,delivery,duration_days,comparison_key,review_required,price,currency,stock_status,purchase_url,expires_at)
 values(manual_id,'manual','ChatGPT Plus','ChatGPT','Plus','代充',30,'hot-test',false,1,'CNY','in_stock','https://hot-manual-test.invalid/1',now()+interval '1 hour');
 select value into job from public.claim_hot_sources(6) value;
 if job is null or job->>'id'<>s.id::text or job->'hot_external_ids'<>'["target"]'::jsonb then raise exception 'hot selection/manual exclusion failed'; end if;
 if exists(select 1 from public.claim_sources(1,s.id)) then raise exception 'full collector overlapped verification'; end if;
 if exists(select 1 from public.claim_hot_sources(6)) then raise exception 'verification double claimed'; end if;
 payload:='[{"external_id":"target","raw_title":"ChatGPT Plus 代充 1个月","platform":"ChatGPT","plan":"Plus","delivery":"代充","duration_days":30,"comparison_key":"hot-test","review_required":false,"price":90,"currency":"CNY","stock_status":"out_of_stock","purchase_url":"https://hot-test.invalid/target"},{"external_id":"untouched","price":1}]';
 perform public.complete_hot_verification((job->>'hot_run_id')::uuid,(job->>'lease_token')::uuid,payload,true);
 if not exists(select 1 from public.offers where id=quote_id and price=90 and stock_status='out_of_stock' and hot_verified_at is not null) then raise exception 'target verification not persisted'; end if;
 if not exists(select 1 from public.offers where id=quote_id and expires_at=last_seen_at+interval '45 minutes') then raise exception 'Hot stock expires before thirty-minute publication can refresh'; end if;
 if not exists(select 1 from public.offers where id=untouched_id and price=100 and active and last_seen_at=original_seen and hot_verified_at is null) then raise exception 'unselected offer overwritten or freshness extended'; end if;
 if not exists(select 1 from public.sources where id=s.id and last_success_at=now()-interval '1 hour' and next_crawl_at=now()+interval '2 hours' and lease_token is null) then raise exception 'verification changed full crawl schedule/heartbeat'; end if;
 begin
  perform public.complete_hot_verification((job->>'hot_run_id')::uuid,(job->>'lease_token')::uuid,'[]',true);
  raise exception 'duplicate completion accepted';
 exception when raise_exception then if sqlerrm='duplicate completion accepted' then raise; end if; end;
 update public.offers set stock_status='in_stock',hot_attempted_at=now()-interval '6 minutes' where id=quote_id;
 update public.sources set hot_next_at=now() where id=s.id;
 select value into other_job from public.claim_hot_sources(1) value;
 perform public.complete_hot_verification((other_job->>'hot_run_id')::uuid,(other_job->>'lease_token')::uuid,'[]',false);
 if not exists(select 1 from public.offers where id=quote_id and active) then raise exception 'partial absence removed target'; end if;
 update public.offers set hot_attempted_at=now()-interval '6 minutes' where id=quote_id;
 update public.sources set hot_next_at=now() where id=s.id;
 select value into other_job from public.claim_hot_sources(1) value;
 perform public.complete_hot_verification((other_job->>'hot_run_id')::uuid,(other_job->>'lease_token')::uuid,'[]',true);
 if exists(select 1 from public.offers where id=quote_id and active) then raise exception 'complete absence retained target'; end if;
 update public.sources set hot_next_at=now() where id=s.id;
 insert into public.offers(source_id,external_id,raw_title,platform,plan,delivery,duration_days,review_required,price,currency,stock_status,purchase_url,expires_at)
 select s.id,'bounded-'||g,'ChatGPT Team','ChatGPT','Team','未知',g,true,20+g::numeric/1000,'CNY','unknown','https://hot-test.invalid/'||g,now()+interval '1 hour' from generate_series(1,121) g;
 select value into other_job from public.claim_hot_sources(6) value;
 if jsonb_array_length(other_job->'hot_external_ids')<>120 then raise exception 'global verification quote cap not respected'; end if;
 perform public.complete_hot_verification((other_job->>'hot_run_id')::uuid,(other_job->>'lease_token')::uuid,'[]',false,'timeout');
 if not exists(select 1 from public.sources where id=s.id and hot_next_at=now()+interval '30 minutes' and lease_token is null) then raise exception 'failed verification cooldown or lease release missing'; end if;
 if has_table_privilege('anon','public.hot_verification_runs','select') or has_function_privilege('anon','public.claim_hot_sources(integer)','execute') then raise exception 'verification access leaked'; end if;
end $$;
rollback;
select 'hot verification invariants passed; fixtures rolled back' result;
