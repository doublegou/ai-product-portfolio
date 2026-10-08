-- One minute dispatch, uniform 15-minute target per shop; spread the queue.
alter table public.sources alter column interval_minutes set default 15;
update public.sources set interval_minutes=15,
 next_crawl_at=now()+((abs(hashtextextended(id::text,0)) % 900) * interval '1 second')
 where enabled;
create or replace function public.claim_sources(batch_size integer default 64, requested_id uuid default null)
returns setof public.sources language plpgsql security definer set search_path=public as $$
begin
 return query with candidates as (
 select id from sources where enabled and (lease_until is null or lease_until < now())
 and ((requested_id is null and next_crawl_at <= now()) or id=requested_id)
 order by next_crawl_at for update skip locked limit least(greatest(batch_size,1),64)
 ) update sources s set lease_until=now()+interval '3 minutes',lease_token=gen_random_uuid()
 from candidates c where s.id=c.id returning s.*;
end $$;


create or replace function public.complete_crawl(p_source_id uuid,p_lease_token uuid,p_run_id uuid,p_offers jsonb,p_complete boolean,p_error text default null)
returns void language plpgsql security definer set search_path=public as $$
declare s sources; item jsonb; old offers; saved offers; seen text[] := '{}';
begin
 select * into s from sources where id=p_source_id for update;
 if s.lease_token is distinct from p_lease_token then raise exception 'lease expired'; end if;
 if p_error is null then
  for item in select value from jsonb_array_elements(p_offers) loop
   select * into old from offers where source_id=s.id and external_id=item->>'external_id';
   insert into offers(source_id,external_id,raw_title,platform,plan,delivery,duration_days,comparison_key,review_required,price,currency,stock_status,purchase_url,raw_data,expires_at)
   values(s.id,item->>'external_id',item->>'raw_title',item->>'platform',item->>'plan',item->>'delivery',nullif(item->>'duration_days','')::integer,item->>'comparison_key',(item->>'review_required')::boolean,(item->>'price')::numeric,item->>'currency',item->>'stock_status',item->>'purchase_url',coalesce(item->'raw_data','{}'),now()+greatest(interval '45 minutes',s.interval_minutes*3*interval '1 minute'))
   on conflict(source_id,external_id) do update set
    raw_title=excluded.raw_title,platform=excluded.platform,plan=excluded.plan,delivery=excluded.delivery,duration_days=excluded.duration_days,comparison_key=excluded.comparison_key,review_required=excluded.review_required,
    price=excluded.price,currency=excluded.currency,stock_status=excluded.stock_status,purchase_url=excluded.purchase_url,raw_data=excluded.raw_data,last_seen_at=now(),expires_at=excluded.expires_at,active=true
   returning * into saved;
   if old.id is null or old.price is distinct from saved.price or old.stock_status is distinct from saved.stock_status or old.currency is distinct from saved.currency then
    insert into price_history(offer_id,price,currency,stock_status) values(saved.id,saved.price,saved.currency,saved.stock_status);
   end if;
   seen:=array_append(seen,item->>'external_id');
  end loop;
  if p_complete then update offers set active=false where source_id=s.id and not(external_id=any(seen)); end if;
 end if;
 update sources set lease_until=null,lease_token=null,
  last_success_at=case when p_error is null then now() else last_success_at end,last_error=left(p_error,1000),
  consecutive_failures=case when p_error is null then 0 else consecutive_failures+1 end,
  next_crawl_at=now()+case when p_error is null then interval_minutes else least(240,interval_minutes*power(2,least(consecutive_failures+1,4))::integer) end*interval '1 minute'
 where id=s.id;
 update crawl_runs set finished_at=now(),status=case when p_error is null then 'success' else 'failed' end,
  offer_count=jsonb_array_length(p_offers),complete_snapshot=p_complete,error=left(p_error,1000) where id=p_run_id and source_id=s.id;
end $$;

-- Old prices should not remain current for a whole day after collection fails.
update public.offers set expires_at=least(expires_at,last_seen_at+interval '45 minutes');
select cron.alter_job(jobid, command := $job$
 delete from public.crawl_runs where started_at<now()-interval '3 days';
 delete from public.price_history where observed_at<now()-interval '30 days';
$job$) from cron.job where jobname='aimarketing-log-retention';
