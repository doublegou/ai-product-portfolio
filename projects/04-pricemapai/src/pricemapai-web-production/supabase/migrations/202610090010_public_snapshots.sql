-- One SQL statement gives the publisher a consistent, public-only dataset.
create function public.build_public_snapshot() returns jsonb
language sql stable security invoker set search_path='' as $$
select jsonb_build_object(
 'generated_at',now(),
 'offers',coalesce((select jsonb_agg(jsonb_build_object(
  'id',o.id,'raw_title',o.raw_title,'platform',o.platform,'plan',o.plan,'delivery',o.delivery,
  'duration_days',o.duration_days,'comparison_key',o.comparison_key,'review_required',o.review_required,
  'price',o.price,'currency',o.currency,'stock_status',o.stock_status,'purchase_url',o.purchase_url,
  'last_seen_at',o.last_seen_at,'expires_at',o.expires_at,
  'sources',jsonb_build_object('name',s.name,'base_url',s.base_url),
  'price_note',o.raw_data->>'price_note','stock_quantity',o.raw_data->'stock_quantity','stock_text',o.raw_data->>'stock_text'
 ) order by o.id) from public.offers o join public.sources s on s.id=o.source_id where o.active and s.enabled),'[]'::jsonb),
 'transit',coalesce((select jsonb_agg(jsonb_build_object('source_id',p.source_id,'data',p.data,
  'last_seen_at',p.last_seen_at,'expires_at',p.expires_at,'collection_error',s.last_error is not null)
  order by p.source_id) from public.transit_snapshots p join public.transit_sources s on s.id=p.source_id where s.enabled),'[]'::jsonb)
);
$$;
revoke all on function public.build_public_snapshot() from public,anon,authenticated;
grant execute on function public.build_public_snapshot() to service_role;

create table public.snapshot_publication (
 id boolean primary key default true check(id),
 lease_token uuid, lease_until timestamptz, last_published_at timestamptz, version text
);
alter table public.snapshot_publication enable row level security;
revoke all on public.snapshot_publication from public,anon,authenticated;
grant all on public.snapshot_publication to service_role;
insert into public.snapshot_publication(id) values(true);
create function public.claim_snapshot_publication() returns uuid
language plpgsql security invoker set search_path='' as $$
declare token uuid:=gen_random_uuid(); claimed uuid;
begin
 update public.snapshot_publication set lease_token=token,lease_until=now()+interval '3 minutes'
 where id and (lease_until is null or lease_until<now())
 returning lease_token into claimed;
 return claimed;
end $$;
create function public.finish_snapshot_publication(p_token uuid,p_version text default null) returns void
language sql security invoker set search_path='' as $$
 update public.snapshot_publication set lease_token=null,lease_until=null,
 last_published_at=case when p_version is not null then now() else last_published_at end,
 version=coalesce(p_version,version) where id and lease_token=p_token;
$$;
revoke all on function public.claim_snapshot_publication(),public.finish_snapshot_publication(uuid,text) from public,anon,authenticated;
grant execute on function public.claim_snapshot_publication(),public.finish_snapshot_publication(uuid,text) to service_role;

create function public.invoke_publish_snapshot() returns bigint
language plpgsql security invoker set search_path='' as $$
declare endpoint text; api_key text; crawler_token text; request_id bigint;
begin
 select regexp_replace(decrypted_secret,'/collect-prices$','/publish-snapshot') into endpoint from vault.decrypted_secrets where name='pricemapai_collector_url';
 select decrypted_secret into api_key from vault.decrypted_secrets where name='pricemapai_collector_api_key';
 select decrypted_secret into crawler_token from vault.decrypted_secrets where name='pricemapai_collector_token';
 if endpoint is null or api_key is null or crawler_token is null then raise exception 'Publisher scheduler secrets have not been configured'; end if;
 select net.http_post(url:=endpoint,headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||api_key,'X-Crawler-Token',crawler_token),body:='{}'::jsonb,timeout_milliseconds:=130000) into request_id;
 return request_id;
end $$;
revoke all on function public.invoke_publish_snapshot() from public,anon,authenticated,service_role;
-- Enable only after publisher credentials and the first static publication succeed.
-- select cron.schedule('pricemapai-publish-snapshot','*/15 * * * *','select public.invoke_publish_snapshot()');

-- Keep this publisher's Cron execution history bounded like the collectors.
select cron.alter_job(jobid,command:=command||E'\n delete from cron.job_run_details where start_time<now()-interval ''3 days'' and jobid in(select jobid from cron.job where jobname=''pricemapai-publish-snapshot'');')
from cron.job where jobname='aimarketing-log-retention' and position('pricemapai-publish-snapshot' in command)=0;
