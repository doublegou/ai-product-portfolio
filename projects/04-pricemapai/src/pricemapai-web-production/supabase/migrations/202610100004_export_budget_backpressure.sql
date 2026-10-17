-- Retain a prepared pending batch when the byte budget is exhausted.
-- Returning a small status commits it; raising would rebuild it every minute.
create or replace function public.export_snapshot_batch(p_force_full boolean default false) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare st public.snapshot_export_state; snapshot jsonb; changes jsonb; payload jsonb; full_export boolean; size_bytes bigint;
begin
 select * into st from public.snapshot_export_state where id for update;
 -- The mirror represents exactly this pending revision, so recovery can turn a
 -- pending delta into a full checkpoint without skipping unacknowledged data.
 if st.pending is not null then
  payload:=st.pending;
  if p_force_full and not (payload->>'full')::boolean then
   select coalesce(jsonb_agg(jsonb_build_object('key',key,'value',document) order by key),'[]') into changes from public.snapshot_export_entities;
   payload:=jsonb_set(jsonb_set(payload,'{changes}',changes),'{full}','true');
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
  select 'transit:'||(row->>'source_id'),public.snapshot_without_collection_times(row) from jsonb_array_elements(snapshot->'transit') row;
  select coalesce(jsonb_agg(change order by key),'[]') into changes from (
   select coalesce(c.key,e.key) as key,
    case when c.key is null then jsonb_build_object('key',e.key,'remove',true)
    when full_export or e.key is null then jsonb_build_object('key',c.key,'value',c.document)
    else (select case when octet_length(diff::text)<octet_length(c.document::text) then jsonb_build_object('key',c.key,'patches',diff) else jsonb_build_object('key',c.key,'value',c.document) end
     from (select public.snapshot_json_diff(e.document,c.document) diff) d) end as change
   from snapshot_current c full join public.snapshot_export_entities e on e.key=c.key
   where (full_export and c.key is not null) or (not full_export and c.document is distinct from e.document)
  ) changed;
  payload:=jsonb_build_object('schema',1,'revision',st.revision+1,'base_revision',st.revision,'full',full_export,'generated_at',snapshot->'generated_at','changes',changes);
  delete from public.snapshot_export_entities e where not exists(select 1 from snapshot_current c where c.key=e.key);
  insert into public.snapshot_export_entities select * from snapshot_current on conflict(key) do update set document=excluded.document where snapshot_export_entities.document is distinct from excluded.document;
  update public.snapshot_export_state set revision=st.revision+1,pending=payload,last_full_at=case when full_export then now() else last_full_at end where id;
 end if;
 -- Bound normal export plus retries to 40MB/day (~1.2GB/month per leg).
 -- The one-time bootstrap is also charged, but allowed below the same cap.
 size_bytes:=octet_length(payload::text);
 if (case when st.budget_day=current_date then st.sent_bytes else 0 end)+size_bytes>40000000 then return jsonb_build_object('budget_exhausted',true,'resume_on',current_date+1); end if;
 update public.snapshot_export_state set budget_day=current_date,sent_bytes=(case when budget_day=current_date then sent_bytes else 0 end)+size_bytes where id;
 return payload;
end $$;
