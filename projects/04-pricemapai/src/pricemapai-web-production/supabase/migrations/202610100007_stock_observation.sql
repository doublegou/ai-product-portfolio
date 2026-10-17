-- Complete snapshots alone establish whole-shop stock state. Unknown is not empty.
alter table public.sources add column availability_state text not null default 'unknown' check(availability_state in ('unknown','available','out_of_stock'));
alter table public.sources add column out_of_stock_since timestamptz;
alter table public.sources add column out_of_stock_confirmations integer not null default 0;
alter table public.crawl_runs add column checked_offer_count integer not null default 0;
alter table public.crawl_runs add column changed_offer_count integer not null default 0;
alter table public.crawl_runs add column new_offer_count integer not null default 0;
create function public.source_stock_interval(since_at timestamptz,confirmations integer,priority boolean) returns integer
language sql stable set search_path='' as $$
 select case when confirmations>=3 and since_at<=now()-interval '14 days' then case when priority then 1440 else 10080 end
 when confirmations>=3 and since_at<=now()-interval '3 days' then 1440
 when since_at<=now()-interval '1 day' then case when priority then 180 else 360 end
 else case when priority then 60 else 180 end end;
$$;
create function public.refresh_source_collection_policy(p_source_id uuid default null) returns integer
language plpgsql security invoker set search_path='' as $$
declare st public.collection_heat_state; changed integer;
begin
 select * into st from public.collection_heat_state where id;
 with heat as(select x->>'id' id,least(1000,greatest(0,(x->>'clicks')::integer)) clicks, case when x ? 'purchase_clicks' then 3*least(1000,greatest(0,coalesce((x->>'purchase_clicks')::integer,0)))+2*least(1000,greatest(0,coalesce((x->>'pricing_clicks')::integer,0)))+least(1000,greatest(0,coalesce((x->>'shop_clicks')::integer,0)))+least(1000,greatest(0,coalesce((x->>'detail_views')::integer,0))) else least(1000,greatest(0,(x->>'clicks')::integer)) end score from jsonb_array_elements(case when st.generated_at>now()-interval '2 hours' then st.sources else '[]'::jsonb end) x),
 activity as(select s.id,coalesce(h.clicks,0) clicks,coalesce(h.score,0) score,
  exists(select 1 from public.price_history ph join public.offers o on o.id=ph.offer_id where o.source_id=s.id and ph.observed_at>now()-interval '1 day') volatile,
  s.created_at,s.consecutive_failures,s.availability_state,s.out_of_stock_since,s.out_of_stock_confirmations from public.sources s left join heat h on h.id=public.merchant_analytics_id(s.base_url) where s.enabled and s.adaptive_enabled),
 ranked as(select *,row_number() over(order by (clicks>=3) desc,score desc,clicks desc,id) heat_rank from activity),
 policy as(select id,case when availability_state='out_of_stock' then public.source_stock_interval(out_of_stock_since,out_of_stock_confirmations,clicks>0) when consecutive_failures>0 then 180 when clicks>=3 and heat_rank<=20 then 10 when volatile then 15 when clicks>0 then 30 when created_at<now()-interval '7 days' then 180 else 60 end minutes,
 case when availability_state='out_of_stock' then 'out_of_stock' when consecutive_failures>0 then 'recovering' when clicks>=3 and heat_rank<=20 then 'hot' when volatile then 'changing' when clicks>0 then 'warm' else 'stable' end tier from ranked)
 update public.sources s set interval_minutes=p.minutes,collection_tier=p.tier,
  next_crawl_at=case when p.minutes<s.interval_minutes then least(s.next_crawl_at,now()+make_interval(secs=>(abs(hashtextextended(s.id::text,0))%600)::integer)) else s.next_crawl_at end
 from policy p where s.id=p.id and (p_source_id is null or s.id=p_source_id) and (s.interval_minutes<>p.minutes or s.collection_tier<>p.tier);
 get diagnostics changed=row_count;
 return changed;
end $$;
-- Prefer purchase intent to browsing, retaining distinct-session hot thresholds.
create or replace function public.apply_collection_heat(p_heat jsonb default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare st public.collection_heat_state; changed integer:=0; transit_changed integer:=0;
begin
 select * into st from public.collection_heat_state where id for update;
 if p_heat is not null and jsonb_typeof(p_heat->'sources')='array' and jsonb_array_length(p_heat->'sources')<=1000
  and (p_heat->>'generated_at')::timestamptz between now()-interval '2 hours' and now()+interval '5 minutes'
  and (st.generated_at is null or (p_heat->>'generated_at')::timestamptz>st.generated_at) then
  if st.generated_at is null or st.generated_at<now()-interval '2 hours' or (not jsonb_path_exists(st.sources,'$[*].purchase_clicks') and jsonb_path_exists(p_heat->'sources','$[*].purchase_clicks')) then st.last_applied_at:=null; end if;
  update public.collection_heat_state set generated_at=(p_heat->>'generated_at')::timestamptz,sources=p_heat->'sources' where id;
  st.generated_at:=(p_heat->>'generated_at')::timestamptz; st.sources:=p_heat->'sources';
 end if;
 if st.last_applied_at>now()-interval '1 hour' then return jsonb_build_object('skipped',true); end if;
 -- Stale/missing analytics never keeps merchants permanently in the hot tier.
 changed:=public.refresh_source_collection_policy();

 with heat as(select x->>'id' id,least(1000,greatest(0,(x->>'clicks')::integer)) clicks, case when x ? 'purchase_clicks' then 3*least(1000,greatest(0,coalesce((x->>'purchase_clicks')::integer,0)))+2*least(1000,greatest(0,coalesce((x->>'pricing_clicks')::integer,0)))+least(1000,greatest(0,coalesce((x->>'shop_clicks')::integer,0)))+least(1000,greatest(0,coalesce((x->>'detail_views')::integer,0))) else least(1000,greatest(0,(x->>'clicks')::integer)) end score from jsonb_array_elements(case when st.generated_at>now()-interval '2 hours' then st.sources else '[]'::jsonb end) x),
 ranked as(select s.*,coalesce(h.clicks,0) clicks,row_number() over(order by (coalesce(h.clicks,0)>=3) desc,coalesce(h.score,0) desc,coalesce(h.clicks,0) desc,s.id) heat_rank from public.transit_sources s left join heat h on h.id=s.id where s.enabled and s.adaptive_enabled),
 policy as(select id,case when failure_count>0 then 180 when clicks>=3 and heat_rank<=5 then 10 when clicks>0 then 15 else 60 end minutes,
 case when failure_count>0 then 'recovering' when clicks>=3 and heat_rank<=5 then 'hot' when clicks>0 then 'warm' else 'stable' end tier from ranked)
 update public.transit_sources s set interval_minutes=p.minutes,collection_tier=p.tier,
  next_crawl_at=case when p.minutes<s.interval_minutes then least(s.next_crawl_at,now()+make_interval(secs=>(abs(hashtextextended(s.id,0))%600)::integer)) else s.next_crawl_at end
 from policy p where s.id=p.id and (s.interval_minutes<>p.minutes or s.collection_tier<>p.tier);
 get diagnostics transit_changed=row_count;
 update public.collection_heat_state set last_applied_at=now() where id;
 return jsonb_build_object('sources_changed',changed,'transit_changed',transit_changed,'heat_fresh',coalesce(st.generated_at>now()-interval '2 hours',false));
end $$;

-- Preserve the existing ingestion/lease/retention logic behind a private wrapper.
alter function public.complete_crawl(uuid,uuid,uuid,jsonb,boolean,text) rename to complete_crawl_ingest;
create function public.complete_crawl(p_source_id uuid,p_lease_token uuid,p_run_id uuid,p_offers jsonb,p_complete boolean,p_error text default null)
returns void language plpgsql security invoker set search_path='' as $$
declare s public.sources; observed integer:=0; changed integer:=0; added integer:=0; missing integer:=0; state text;
begin
 select * into s from public.sources where id=p_source_id for update;
 if p_lease_token is null or s.lease_token is distinct from p_lease_token then raise exception 'lease expired'; end if;
 if p_error is null then
  select count(*),count(*) filter(where o.id is not null and (o.price is distinct from (x->>'price')::numeric or o.currency is distinct from x->>'currency' or o.stock_status is distinct from x->>'stock_status')),
  count(*) filter(where o.id is null) into observed,changed,added
  from jsonb_array_elements(p_offers) x left join public.offers o on o.source_id=s.id and o.external_id=x->>'external_id';
  if p_complete then
   select count(*) into missing from public.offers o where o.source_id=s.id and o.active and not exists(select 1 from jsonb_array_elements(p_offers) x where x->>'external_id'=o.external_id);
  end if;
 end if;
 perform public.complete_crawl_ingest(p_source_id,p_lease_token,p_run_id,p_offers,p_complete,p_error);
 update public.crawl_runs set checked_offer_count=observed+missing,changed_offer_count=changed+missing,new_offer_count=added where id=p_run_id and source_id=p_source_id;
 if p_error is null and p_complete then
  select case when count(*) filter(where stock_status='in_stock')>0 then 'available'
    when count(*)=0 or bool_and(stock_status='out_of_stock') then 'out_of_stock' else 'unknown' end into state
  from public.offers where source_id=s.id and active;
  update public.sources set availability_state=state,
   out_of_stock_since=case when state='out_of_stock' then coalesce(s.out_of_stock_since,now()) else null end,
   out_of_stock_confirmations=case when state='out_of_stock' then s.out_of_stock_confirmations+1 else 0 end where id=s.id;
 end if;
 perform public.refresh_source_collection_policy(s.id);
 if p_error is null then
  update public.sources set next_crawl_at=now()+make_interval(mins=>interval_minutes) where id=s.id;
  update public.offers o set expires_at=now()+greatest(interval '45 minutes',make_interval(mins=>current_source.interval_minutes*3))
   from public.sources current_source where current_source.id=s.id and o.source_id=s.id
   and exists(select 1 from jsonb_array_elements(p_offers) x where x->>'external_id'=o.external_id);
 end if;
end $$;
revoke all on function public.source_stock_interval(timestamptz,integer,boolean),public.refresh_source_collection_policy(uuid),public.complete_crawl(uuid,uuid,uuid,jsonb,boolean,text),public.complete_crawl_ingest(uuid,uuid,uuid,jsonb,boolean,text) from public,anon,authenticated;
grant execute on function public.source_stock_interval(timestamptz,integer,boolean),public.refresh_source_collection_policy(uuid),public.complete_crawl(uuid,uuid,uuid,jsonb,boolean,text),public.complete_crawl_ingest(uuid,uuid,uuid,jsonb,boolean,text) to service_role;
