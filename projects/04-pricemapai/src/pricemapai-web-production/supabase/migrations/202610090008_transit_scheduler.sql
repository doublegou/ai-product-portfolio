create function public.invoke_collect_transit() returns bigint
language plpgsql security invoker set search_path='' as $$
declare endpoint text; api_key text; crawler_token text; request_id bigint;
begin
 select regexp_replace(decrypted_secret,'/collect-prices$','/collect-transit') into endpoint from vault.decrypted_secrets where name='pricemapai_collector_url';
 select decrypted_secret into api_key from vault.decrypted_secrets where name='pricemapai_collector_api_key';
 select decrypted_secret into crawler_token from vault.decrypted_secrets where name='pricemapai_collector_token';
 if endpoint is null or endpoint not like '%/collect-transit' or api_key is null or crawler_token is null then raise exception 'Collector scheduler secrets have not been configured';end if;
 select net.http_post(url:=endpoint,headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||api_key,'X-Crawler-Token',crawler_token),body:='{}'::jsonb,timeout_milliseconds:=130000) into request_id;
 return request_id;
end $$;
revoke all on function public.invoke_collect_transit() from public,anon,authenticated,service_role;
select cron.schedule('pricemapai-collect-transit','* * * * *','select public.invoke_collect_transit()');
select cron.alter_job(jobid,command:=$job$
 delete from public.crawl_runs where started_at<now()-interval '3 days';
 delete from public.transit_crawl_runs where started_at<now()-interval '3 days';
 delete from public.price_history where observed_at<now()-interval '30 days';
 delete from cron.job_run_details where start_time<now()-interval '3 days'
   and jobid in(select jobid from cron.job where jobname in('pricemapai-collect-prices','pricemapai-collect-transit','aimarketing-log-retention','aimarketing-price-refresh'));
$job$) from cron.job where jobname='aimarketing-log-retention';
