-- Run against a linked project with: supabase db query --linked --file tests/database.sql
-- All fixtures live inside a rolled-back transaction.
begin;
do $$
declare s sources; run_id uuid; count_before integer; count_after integer; payload jsonb;
begin
 insert into sources(name,base_url,collector) values('transaction-test','https://transaction-test.example.com/','json') returning * into s;
 select * into s from claim_sources(1,s.id);
 if s.lease_token is null then raise exception 'claim did not acquire lease'; end if;
 if exists(select 1 from claim_sources(1,s.id)) then raise exception 'double claim allowed'; end if;
 insert into crawl_runs(source_id) values(s.id) returning id into run_id;
 payload:='[{"external_id":"1","raw_title":"ChatGPT Plus 代充 1个月","platform":"ChatGPT","plan":"Plus","delivery":"代充","duration_days":30,"comparison_key":"ChatGPT:Plus:代充:30","review_required":false,"price":100,"currency":"CNY","stock_status":"in_stock","purchase_url":"https://transaction-test.example.com/buy/1"}]';
 perform complete_crawl(s.id,s.lease_token,run_id,payload,true);
 if not exists(select 1 from offers where source_id=s.id and expires_at between now()+interval '44 minutes' and now()+interval '46 minutes') then raise exception '15-minute sources must expire after 45 minutes'; end if;
 if not exists(select 1 from sources where id=s.id and next_crawl_at between now()+interval '14 minutes' and now()+interval '16 minutes') then raise exception '15-minute schedule not persisted'; end if;
 select count(*) into count_before from price_history h join offers o on o.id=h.offer_id where o.source_id=s.id;
 if count_before<>1 then raise exception 'initial history missing'; end if;
 select * into s from claim_sources(1,s.id);
 insert into crawl_runs(source_id) values(s.id) returning id into run_id;
 perform complete_crawl(s.id,s.lease_token,run_id,payload,true);
 select count(*) into count_after from price_history h join offers o on o.id=h.offer_id where o.source_id=s.id;
 if count_after<>count_before then raise exception 'unchanged prices generated duplicate history'; end if;
 select * into s from claim_sources(1,s.id);
 insert into crawl_runs(source_id) values(s.id) returning id into run_id;
 perform complete_crawl(s.id,s.lease_token,run_id,'[]',false,'source HTTP 503');
 if not exists(select 1 from offers where source_id=s.id and active) then raise exception 'failure removed previous offer'; end if;
 select * into s from claim_sources(1,s.id);
 insert into crawl_runs(source_id) values(s.id) returning id into run_id;
 perform complete_crawl(s.id,s.lease_token,run_id,jsonb_set(payload,'{0,price}','110'),false);
 select count(*) into count_after from price_history h join offers o on o.id=h.offer_id where o.source_id=s.id;
 if count_after<>2 then raise exception 'changed price not recorded'; end if;
 select * into s from claim_sources(1,s.id);
 insert into crawl_runs(source_id) values(s.id) returning id into run_id;
 perform complete_crawl(s.id,s.lease_token,run_id,'[]',true);
 if exists(select 1 from offers where source_id=s.id and active) then raise exception 'complete snapshot did not retire missing offer'; end if;
 if has_table_privilege('anon','offers','select') then raise exception 'anonymous access leaked'; end if;
end $$;
rollback;
select 'transaction invariants passed; fixtures rolled back' as result;
