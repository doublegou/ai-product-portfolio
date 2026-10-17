-- Minute dispatch, per-source five-minute due time; no Cloudflare Cron added.
create function public.invoke_verify_hot_offers() returns bigint
language plpgsql security invoker set search_path='' as $$
declare endpoint text; api_key text; crawler_token text; request_id bigint;
begin
 select regexp_replace(decrypted_secret,'/collect-prices$','/verify-hot-offers') into endpoint from vault.decrypted_secrets where name='pricemapai_collector_url';
 select decrypted_secret into api_key from vault.decrypted_secrets where name='pricemapai_collector_api_key';
 select decrypted_secret into crawler_token from vault.decrypted_secrets where name='pricemapai_collector_token';
 if endpoint is null or api_key is null or crawler_token is null then raise exception 'Collector scheduler secrets have not been configured'; end if;
 select net.http_post(url:=endpoint,headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||api_key,'X-Crawler-Token',crawler_token),body:='{}'::jsonb,timeout_milliseconds:=130000) into request_id;
 return request_id;
end $$;
revoke all on function public.invoke_verify_hot_offers() from public,anon,authenticated,service_role;
select cron.schedule('pricemapai-verify-hot-offers','* * * * *','select public.invoke_verify_hot_offers()');
