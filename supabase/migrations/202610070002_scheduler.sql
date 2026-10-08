create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;
create function public.invoke_price_crawler() returns bigint
language plpgsql security definer set search_path=public,extensions as $$
declare endpoint text; token text; request_id bigint;
begin
 select decrypted_secret into endpoint from vault.decrypted_secrets where name='aimarketing_crawl_url';
 select decrypted_secret into token from vault.decrypted_secrets where name='aimarketing_crawl_token';
 if endpoint is null or token is null then raise exception 'Crawler secrets have not been configured'; end if;
 select net.http_post(url:=endpoint,headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||token),body:='{}'::jsonb,timeout_milliseconds:=120000) into request_id;
 return request_id;
end $$;
revoke all on function public.invoke_price_crawler() from public,anon,authenticated;
grant execute on function public.invoke_price_crawler() to service_role;
select cron.schedule('aimarketing-price-refresh','*/5 * * * *','select public.invoke_price_crawler()');
select cron.schedule('aimarketing-log-retention','23 19 * * *', $job$
 delete from public.crawl_runs where started_at<now()-interval '30 days';
 delete from public.price_history where observed_at<now()-interval '90 days';
$job$);
