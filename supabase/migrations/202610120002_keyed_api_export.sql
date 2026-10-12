-- Stable model/group deltas and independent two-hour monitoring updates.
alter table public.snapshot_export_state add column last_monitoring_at timestamptz;
create table public.snapshot_export_runs (
 id bigint generated always as identity primary key, created_at timestamptz not null default now(),
 revision bigint not null, payload_bytes bigint not null, full_export boolean not null,
 status text not null check(status in ('exported','budget_exhausted')),
 changes integer, offers_bytes bigint, transit_bytes bigint, freshness_bytes bigint,
 acknowledged_at timestamptz
);
alter table public.snapshot_export_runs enable row level security;
revoke all on public.snapshot_export_runs from public,anon,authenticated;
grant select,insert,update,delete on public.snapshot_export_runs to service_role;
grant usage on sequence public.snapshot_export_runs_id_seq to service_role;
create index on public.snapshot_export_runs(created_at);

create function public.snapshot_index_transit(p_row jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare prices jsonb; n integer;
begin
 if jsonb_typeof(p_row#>'{data,prices}')='object' then return p_row; end if;
 if jsonb_typeof(p_row#>'{data,prices}') is distinct from 'array' then raise exception 'Invalid transit prices'; end if;
 n:=jsonb_array_length(p_row#>'{data,prices}');
 if exists(select 1 from jsonb_array_elements(p_row#>'{data,prices}')p where coalesce(p->>'id','')='') then raise exception 'Missing stable price ID'; end if;
 select jsonb_object_agg(md5(p->>'id'),p) into prices from jsonb_array_elements(p_row#>'{data,prices}')p;
 if (select count(*) from jsonb_object_keys(coalesce(prices,'{}')))<>n then raise exception 'Duplicate price ID'; end if;
 return jsonb_set(p_row,'{data,prices}',coalesce(prices,'{}'));
end $$;

create function public.snapshot_hold_price(current_price jsonb,old_price jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare price jsonb:=current_price; k text;
 keys text[]:=array['publicMonitoring','cacheUsage','sevenDayRate','sevenDaySamples','recentSampleBits','latestLatencyMs','avgLatency7dMs','lastCheckedAt','monitoringScopeId','scope'];
begin
 if old_price is null then return price; end if;
 for k in select unnest(keys) loop
  price:=price-k;
  if old_price ? k then price:=price||jsonb_build_object(k,old_price->k); end if;
 end loop;
 return price;
end $$;

create function public.snapshot_hold_monitoring(current_row jsonb,previous_row jsonb,due boolean) returns jsonb
language plpgsql immutable set search_path='' as $$
declare result jsonb:=current_row; k text; prices jsonb;
 station_keys text[]:=array['publicMonitoring','availability','performance','monitoringError'];
begin
 if due or previous_row is null then return result; end if;
 for k in select unnest(station_keys) loop
  result:=result#-array['data',k];
  if previous_row->'data' ? k then result:=jsonb_set(result,array['data',k],previous_row->'data'->k); end if;
 end loop;
 select jsonb_object_agg(key,public.snapshot_hold_price(value,previous_row#>array['data','prices',key])) into prices
 from jsonb_each(current_row#>'{data,prices}');
 result:=jsonb_set(result,'{data,prices}',coalesce(prices,'{}'));
 return result;
end $$;

-- Normalize the prepared mirror without changing revisions or charging an export.
-- An already pending schema-1 batch stays byte-for-byte retryable; its successor
-- uses schema 2 and Cloudflare normalizes that acknowledged checkpoint locally.
update public.snapshot_export_entities set document=public.snapshot_index_transit(document) where key like 'transit:%';
update public.snapshot_export_state set last_monitoring_at=now() where id;
create or replace function public.export_snapshot_batch(p_force_full boolean default false) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare st public.snapshot_export_state; snapshot jsonb; changes jsonb; payload jsonb; full_export boolean; size_bytes bigint; monitoring_due boolean;
begin
 select * into st from public.snapshot_export_state where id for update;
 monitoring_due:=st.last_monitoring_at is null or st.last_monitoring_at<=now()-interval '2 hours';
 -- The mirror represents exactly this pending revision, so recovery can turn a
 -- pending delta into a full checkpoint without skipping unacknowledged data.
 if st.pending is not null then
  payload:=st.pending;
  if p_force_full and not (payload->>'full')::boolean then
   select coalesce(jsonb_agg(jsonb_build_object('key',key,'value',document) order by key),'[]') into changes from public.snapshot_export_entities;
   payload:=jsonb_set(jsonb_set(payload,'{changes}',changes),'{full}','true');
   payload:=jsonb_set(payload,'{schema}','2');
   update public.snapshot_export_state set pending=payload,last_full_at=now() where id;
  end if;
 else
  snapshot:=public.build_public_snapshot();
  full_export:=p_force_full or st.revision=0 or st.last_full_at<now()-interval '1 day';
  create temporary table if not exists snapshot_current(key text primary key,document jsonb not null) on commit drop;
  truncate snapshot_current;
  insert into snapshot_current
  select 'offers:'||(row->>'id'),
    (row-'last_seen_at'-'expires_at')||jsonb_build_object('_source_id',o.source_id)||
    case when o.last_seen_at is distinct from s.last_success_at then jsonb_build_object('last_seen_at',o.last_seen_at,'expires_at',o.expires_at) else '{}'::jsonb end
  from jsonb_array_elements(snapshot->'offers') row join public.offers o on o.id=(row->>'id')::uuid join public.sources s on s.id=o.source_id;
  insert into snapshot_current
  select 'freshness:'||s.id,jsonb_build_object('last_seen_at',s.last_success_at,'expires_at',(select max(o.expires_at) from public.offers o where o.source_id=s.id and o.active and o.last_seen_at=s.last_success_at))
  from public.sources s where s.enabled and exists(select 1 from public.offers o where o.source_id=s.id and o.active);
  insert into snapshot_current
  select 'transit:'||(row->>'source_id'),public.snapshot_hold_monitoring(public.snapshot_index_transit(public.snapshot_without_collection_times(row)),e.document,monitoring_due)
  from jsonb_array_elements(snapshot->'transit') row left join public.snapshot_export_entities e on e.key='transit:'||(row->>'source_id');
  select coalesce(jsonb_agg(change order by key),'[]') into changes from (
   select coalesce(c.key,e.key) as key,
    case when c.key is null then jsonb_build_object('key',e.key,'remove',true)
    when full_export or e.key is null then jsonb_build_object('key',c.key,'value',c.document)
    else (select case when octet_length(diff::text)<octet_length(c.document::text) then jsonb_build_object('key',c.key,'patches',diff) else jsonb_build_object('key',c.key,'value',c.document) end
     from (select public.snapshot_json_diff(e.document,c.document) diff) d) end as change
   from snapshot_current c full join public.snapshot_export_entities e on e.key=c.key
   where (full_export and c.key is not null) or (not full_export and c.document is distinct from e.document)
  ) changed;
  payload:=jsonb_build_object('schema',2,'revision',st.revision+1,'base_revision',st.revision,'full',full_export,'generated_at',snapshot->'generated_at','changes',changes);
  delete from public.snapshot_export_entities e where not exists(select 1 from snapshot_current c where c.key=e.key);
  insert into public.snapshot_export_entities select * from snapshot_current on conflict(key) do update set document=excluded.document where snapshot_export_entities.document is distinct from excluded.document;
  update public.snapshot_export_state set revision=st.revision+1,pending=payload,last_monitoring_at=case when monitoring_due then now() else last_monitoring_at end,last_full_at=case when full_export then now() else last_full_at end where id;
 end if;
 -- Bound normal export plus retries to 60MB/day (~1.8GB/month per leg).
 -- The one-time bootstrap is also charged, but allowed below the same cap.
 size_bytes:=octet_length(payload::text);
 if (case when st.budget_day=current_date then st.sent_bytes else 0 end)+size_bytes>60000000 then
  insert into public.snapshot_export_runs(revision,payload_bytes,full_export,status) values((payload->>'revision')::bigint,size_bytes,(payload->>'full')::boolean,'budget_exhausted');
  return jsonb_build_object('budget_exhausted',true,'resume_on',current_date+1);
 end if;
 update public.snapshot_export_state set budget_day=current_date,sent_bytes=(case when budget_day=current_date then sent_bytes else 0 end)+size_bytes where id;
 insert into public.snapshot_export_runs(revision,payload_bytes,full_export,status,changes,offers_bytes,transit_bytes,freshness_bytes)
 select (payload->>'revision')::bigint,size_bytes,(payload->>'full')::boolean,'exported',jsonb_array_length(payload->'changes'),
 coalesce(sum(octet_length(ch::text)) filter(where ch->>'key' like 'offers:%'),0),
 coalesce(sum(octet_length(ch::text)) filter(where ch->>'key' like 'transit:%'),0),
 coalesce(sum(octet_length(ch::text)) filter(where ch->>'key' like 'freshness:%'),0)
 from jsonb_array_elements(payload->'changes')ch;
 return payload;
end $$;


alter function public.export_snapshot_batch(boolean) set statement_timeout='30s';
create or replace function public.ack_snapshot_batch(p_revision bigint) returns void
language plpgsql security invoker set search_path='' as $$
begin
 update public.snapshot_export_state set pending=null where id and revision=p_revision;
 update public.snapshot_export_runs set acknowledged_at=now() where revision=p_revision and status='exported' and acknowledged_at is null;
end $$;
select cron.alter_job(job_id:=jobid,command:=command||E'\n delete from public.snapshot_export_runs where created_at<now()-interval ''30 days'';')
from cron.job where jobname='aimarketing-log-retention';
notify pgrst,'reload schema';
