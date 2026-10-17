-- Compare like-for-like, fresh, sellable offers across distinct merchants.
create function public.collection_value_signals() returns table(source_id uuid,low_price_guard boolean,change_density numeric,changed_runs bigint)
language sql stable set search_path='' as $$
 with merchant_prices as (
  select o.source_id,o.comparison_key,o.currency,o.delivery,o.duration_days,min(o.price) price
  from public.offers o join public.sources s on s.id=o.source_id
  where s.enabled and o.active and not o.review_required and o.comparison_key is not null
   and o.stock_status='in_stock' and o.expires_at>now()
  group by o.source_id,o.comparison_key,o.currency,o.delivery,o.duration_days
 ), ranked as (
  select *,dense_rank() over(partition by comparison_key,currency,delivery,duration_days order by price) price_rank,
   count(*) over(partition by comparison_key,currency,delivery,duration_days) competitors
  from merchant_prices
 ), guards as (
  select source_id,bool_or(competitors>=2 and price_rank=1) low_price_guard from ranked group by source_id
 ), changes as (
  select source_id,sum(changed_offer_count)::numeric/nullif(sum(checked_offer_count-new_offer_count),0) change_density,
   count(*) filter(where changed_offer_count>0) changed_runs
  from public.crawl_runs where status='success' and started_at>now()-interval '24 hours'
  group by source_id
 ) select s.id,coalesce(g.low_price_guard,false),coalesce(c.change_density,0),coalesce(c.changed_runs,0)
 from public.sources s left join guards g on g.source_id=s.id left join changes c on c.source_id=s.id;
$$;
create or replace function public.refresh_source_collection_policy(p_source_id uuid default null) returns integer
language plpgsql security invoker set search_path='' as $$
declare st public.collection_heat_state; changed integer;
begin
 select * into st from public.collection_heat_state where id;
 with heat as (
  select x->>'id' id,coalesce((x->>'clicks')::integer,0) clicks,
   case when x ? 'purchase_clicks' then 3*coalesce((x->>'purchase_clicks')::integer,0)
    +2*coalesce((x->>'pricing_clicks')::integer,0)+coalesce((x->>'shop_clicks')::integer,0)
    +coalesce((x->>'detail_views')::integer,0) else coalesce((x->>'clicks')::integer,0) end score
  from jsonb_array_elements(case when st.generated_at>now()-interval '2 hours' then st.sources else '[]'::jsonb end) x
 ), activity as (
  select s.*,coalesce(h.clicks,0) clicks,coalesce(h.score,0) score,v.low_price_guard,v.change_density,v.changed_runs
  from public.sources s join public.collection_value_signals() v on v.source_id=s.id
  left join heat h on h.id=public.merchant_analytics_id(s.base_url) where s.enabled and s.adaptive_enabled
 ), ranked as (
  select *,row_number() over(order by (clicks>=3 and consecutive_failures=0 and availability_state<>'out_of_stock') desc,score desc,clicks desc,id) heat_rank
  from activity
 ), policy as (
  select id,
   case when availability_state='out_of_stock' then public.source_stock_interval(out_of_stock_since,out_of_stock_confirmations,clicks>0 or low_price_guard)
    when consecutive_failures>0 then case when clicks>0 or low_price_guard then 60 else 180 end
    when clicks>=3 and heat_rank<=20 then 10
    when changed_runs>=2 and change_density>=0.20 then 15
    when changed_runs>=2 and change_density>=0.05 and low_price_guard then 30
    when clicks>0 or created_at>now()-interval '1 day' then 30
    when low_price_guard or (changed_runs>=2 and change_density>=0.05) then 60
    when created_at<now()-interval '7 days' then 180 else 60 end minutes,
   case when availability_state='out_of_stock' then 'out_of_stock'
    when consecutive_failures>0 then 'recovering'
    when clicks>=3 and heat_rank<=20 then 'hot'
    when changed_runs>=2 and change_density>=0.20 then 'changing'
    when changed_runs>=2 and change_density>=0.05 and low_price_guard then 'core'
    when clicks>0 or created_at>now()-interval '1 day' then 'warm'
    when low_price_guard then 'lowprice_guard'
    when changed_runs>=2 and change_density>=0.05 then 'watch' else 'stable' end tier
  from ranked
 ) update public.sources s set interval_minutes=p.minutes,collection_tier=p.tier,
  next_crawl_at=case when p.minutes<s.interval_minutes then least(s.next_crawl_at,now()+make_interval(secs=>(abs(hashtextextended(s.id::text,0))%600)::integer)) else s.next_crawl_at end
 from policy p where s.id=p.id and (p_source_id is null or s.id=p_source_id)
  and (s.interval_minutes<>p.minutes or s.collection_tier<>p.tier);
 get diagnostics changed=row_count;
 return changed;
end $$;
revoke all on function public.collection_value_signals() from public,anon,authenticated;
grant execute on function public.collection_value_signals() to service_role;
-- Activate immediately; old runs without metrics cannot be mistaken for changes.
select public.refresh_source_collection_policy();
