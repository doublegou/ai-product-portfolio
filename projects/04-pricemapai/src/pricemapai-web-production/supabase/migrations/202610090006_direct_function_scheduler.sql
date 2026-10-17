-- Keep the collector and its minute scheduler in the same Supabase project.
-- Credentials are provisioned separately in Vault, never in migration history.
create or replace function public.invoke_collect_prices() returns bigint
language plpgsql security invoker set search_path = '' as $$
declare endpoint text; api_key text; crawler_token text; request_id bigint;
begin
 select decrypted_secret into endpoint from vault.decrypted_secrets where name='pricemapai_collector_url';
 select decrypted_secret into api_key from vault.decrypted_secrets where name='pricemapai_collector_api_key';
 select decrypted_secret into crawler_token from vault.decrypted_secrets where name='pricemapai_collector_token';
 if endpoint is null or api_key is null or crawler_token is null then
   raise exception 'Collector scheduler secrets have not been configured';
 end if;
 select net.http_post(
   url := endpoint,
   headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||api_key,'X-Crawler-Token',crawler_token),
   body := '{}'::jsonb,
   timeout_milliseconds := 130000
 ) into request_id;
 return request_id;
end $$;
revoke all on function public.invoke_collect_prices() from public, anon, authenticated, service_role;

select cron.alter_job(jobid, active := false)
from cron.job where jobname='aimarketing-price-refresh';
select cron.schedule('pricemapai-collect-prices','* * * * *','select public.invoke_collect_prices()');

select cron.alter_job(jobid, command := $job$
 delete from public.crawl_runs where started_at<now()-interval '3 days';
 delete from public.price_history where observed_at<now()-interval '30 days';
 delete from cron.job_run_details where start_time<now()-interval '3 days'
   and jobid in (select jobid from cron.job where jobname in ('pricemapai-collect-prices','aimarketing-log-retention','aimarketing-price-refresh'));
$job$) from cron.job where jobname='aimarketing-log-retention';
