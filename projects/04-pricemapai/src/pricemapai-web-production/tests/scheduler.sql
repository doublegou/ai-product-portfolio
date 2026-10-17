-- Check access boundaries without making a network request or exposing Vault.
begin;
do $$
declare role_name text;
begin
 foreach role_name in array array['anon','authenticated','service_role'] loop
   if has_function_privilege(role_name,'public.invoke_collect_prices()','execute') or has_function_privilege(role_name,'public.invoke_collect_transit()','execute') then
     raise exception 'Scheduler invocation exposed to role %', role_name;
   end if;
 end loop;
 if (select count(*) from cron.job where jobname='pricemapai-collect-prices' and active and schedule='* * * * *' and username='postgres') <> 1 then
   raise exception 'Expected one active minute collector schedule owned by postgres';
 end if;
 if (select count(*) from cron.job where jobname='pricemapai-collect-transit' and active and schedule='* * * * *' and username='postgres') <> 1 then raise exception 'Missing API relay schedule';end if;
 if exists(select 1 from cron.job where jobname='aimarketing-price-refresh' and active) then
   raise exception 'Legacy collector schedule is still enabled';
 end if;
end $$;
rollback;
select 'scheduler permissions and single active schedule passed' as result;
