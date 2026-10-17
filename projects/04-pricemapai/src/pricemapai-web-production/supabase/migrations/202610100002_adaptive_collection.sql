alter table public.sources drop constraint sources_interval_minutes_check;
alter table public.sources add constraint sources_interval_minutes_check check(interval_minutes between 10 and 10080);
alter table public.transit_sources drop constraint transit_sources_interval_minutes_check;
alter table public.transit_sources add constraint transit_sources_interval_minutes_check check(interval_minutes between 10 and 10080);
alter table public.sources add column adaptive_enabled boolean not null default true;
alter table public.sources add column collection_tier text not null default 'normal';
alter table public.transit_sources add column adaptive_enabled boolean not null default true;
alter table public.transit_sources add column collection_tier text not null default 'normal';
create table public.collection_heat_state (
 id boolean primary key default true check(id), generated_at timestamptz,
 sources jsonb not null default '[]', last_applied_at timestamptz
);
insert into public.collection_heat_state(id) values(true);
alter table public.collection_heat_state enable row level security;
revoke all on public.collection_heat_state from public,anon,authenticated;
grant all on public.collection_heat_state to service_role;

create function public.merchant_analytics_id(url text) returns text
language sql immutable set search_path='' as $$
 with u as(select regexp_replace(split_part(split_part(url,'?',1),'#',1),'^https?://','','i') value)
 select lower(split_part(value,'/',1))||rtrim(substr(value,length(split_part(value,'/',1))+1),'/') from u;
$$;

create function public.apply_collection_heat(p_heat jsonb default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare st public.collection_heat_state; changed integer:=0; transit_changed integer:=0;
begin
 select * into st from public.collection_heat_state where id for update;
 if p_heat is not null and jsonb_typeof(p_heat->'sources')='array' and jsonb_array_length(p_heat->'sources')<=1000
  and (p_heat->>'generated_at')::timestamptz between now()-interval '2 hours' and now()+interval '5 minutes'
  and (st.generated_at is null or (p_heat->>'generated_at')::timestamptz>st.generated_at) then
  update public.collection_heat_state set generated_at=(p_heat->>'generated_at')::timestamptz,sources=p_heat->'sources' where id;
  st.generated_at:=(p_heat->>'generated_at')::timestamptz; st.sources:=p_heat->'sources';
 end if;
 if st.last_applied_at>now()-interval '1 hour' then return jsonb_build_object('skipped',true); end if;
 -- Stale/missing analytics never keeps merchants permanently in the hot tier.
 with heat as(select x->>'id' id,least(1000,greatest(0,(x->>'clicks')::integer)) clicks from jsonb_array_elements(case when st.generated_at>now()-interval '2 hours' then st.sources else '[]'::jsonb end) x),
 activity as(select s.id,coalesce(h.clicks,0) clicks,
  exists(select 1 from public.price_history ph join public.offers o on o.id=ph.offer_id where o.source_id=s.id and ph.observed_at>now()-interval '1 day') volatile,
  s.created_at,s.consecutive_failures from public.sources s left join heat h on h.id=public.merchant_analytics_id(s.base_url) where s.enabled and s.adaptive_enabled),
 ranked as(select *,row_number() over(order by clicks desc,id) heat_rank from activity),
 policy as(select id,case when consecutive_failures>0 then 180 when clicks>=3 and heat_rank<=20 then 10 when volatile then 15 when clicks>0 then 30 when created_at<now()-interval '7 days' then 180 else 60 end minutes,
 case when consecutive_failures>0 then 'recovering' when clicks>=3 and heat_rank<=20 then 'hot' when volatile then 'changing' when clicks>0 then 'warm' else 'stable' end tier from ranked)
 update public.sources s set interval_minutes=p.minutes,collection_tier=p.tier,
  next_crawl_at=case when p.minutes<s.interval_minutes then least(s.next_crawl_at,now()+make_interval(secs=>(abs(hashtextextended(s.id::text,0))%600)::integer)) else s.next_crawl_at end
 from policy p where s.id=p.id and (s.interval_minutes<>p.minutes or s.collection_tier<>p.tier);
 get diagnostics changed=row_count;
 with heat as(select x->>'id' id,least(1000,greatest(0,(x->>'clicks')::integer)) clicks from jsonb_array_elements(case when st.generated_at>now()-interval '2 hours' then st.sources else '[]'::jsonb end) x),
 ranked as(select s.*,coalesce(h.clicks,0) clicks,row_number() over(order by coalesce(h.clicks,0) desc,s.id) heat_rank from public.transit_sources s left join heat h on h.id=s.id where s.enabled and s.adaptive_enabled),
 policy as(select id,case when failure_count>0 then 180 when clicks>=3 and heat_rank<=5 then 10 when clicks>0 then 15 else 60 end minutes,
 case when failure_count>0 then 'recovering' when clicks>=3 and heat_rank<=5 then 'hot' when clicks>0 then 'warm' else 'stable' end tier from ranked)
 update public.transit_sources s set interval_minutes=p.minutes,collection_tier=p.tier,
  next_crawl_at=case when p.minutes<s.interval_minutes then least(s.next_crawl_at,now()+make_interval(secs=>(abs(hashtextextended(s.id,0))%600)::integer)) else s.next_crawl_at end
 from policy p where s.id=p.id and (s.interval_minutes<>p.minutes or s.collection_tier<>p.tier);
 get diagnostics transit_changed=row_count;
 update public.collection_heat_state set last_applied_at=now() where id;
 return jsonb_build_object('sources_changed',changed,'transit_changed',transit_changed,'heat_fresh',coalesce(st.generated_at>now()-interval '2 hours',false));
end $$;
revoke all on function public.merchant_analytics_id(text),public.apply_collection_heat(jsonb) from public,anon,authenticated;
grant execute on function public.merchant_analytics_id(text),public.apply_collection_heat(jsonb) to service_role;
