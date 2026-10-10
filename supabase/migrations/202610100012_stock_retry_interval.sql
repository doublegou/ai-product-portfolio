-- Keep long stock-observation intervals during transport failures.
create or replace function public.complete_crawl(p_source_id uuid,p_lease_token uuid,p_run_id uuid,p_offers jsonb,p_complete boolean,p_error text default null)
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
 elsif s.adaptive_enabled then
  -- A weekly observation must not become a four-hour retry loop on failure.
  update public.sources set next_crawl_at=now()+make_interval(mins=>greatest(interval_minutes,least(240,interval_minutes*power(2,least(consecutive_failures,4))::integer))) where id=s.id;
 end if;
end $$;
