-- Independent verification does not advance the full-shop heartbeat or schedule.
alter table public.sources add column hot_next_at timestamptz not null default now();
alter table public.offers add column hot_attempted_at timestamptz;
alter table public.offers add column hot_verified_at timestamptz;
create table public.hot_verification_runs (
 id uuid primary key default gen_random_uuid(),source_id uuid not null references public.sources(id) on delete cascade,
 lease_token uuid not null,offer_ids uuid[] not null,started_at timestamptz not null default now(),
 finished_at timestamptz,status text not null default 'running',verified_count integer not null default 0,error text
);
alter table public.hot_verification_runs enable row level security;
revoke all on public.hot_verification_runs from public,anon,authenticated;
grant all on public.hot_verification_runs to service_role;
create index hot_verification_runs_source_time on public.hot_verification_runs(source_id,started_at desc);
create function public.claim_hot_sources(batch_size integer default 6) returns setof jsonb
language plpgsql security invoker set search_path='' as $$
declare src public.sources; ids uuid[]; job_id uuid; candidate record;
begin
 for candidate in
  with top_offers as (
   select o.*,row_number() over(partition by o.platform,o.plan,o.delivery,o.duration_days order by o.price,o.id) rank
   from public.offers o join public.sources s on s.id=o.source_id
   where s.enabled and s.adaptive_enabled and s.consecutive_failures=0 and s.availability_state<>'out_of_stock'
    and o.active and o.expires_at>now() and o.stock_status in ('in_stock','unknown')
    and not o.review_required and o.currency='CNY' and o.platform='ChatGPT' and o.plan in ('Plus','Team')
  ) , selected as (
   select * from top_offers where rank<=20 order by rank,price,id limit 120
  ), due as (
   select source_id,array_agg(id) ids,min(hot_attempted_at) attempted from selected
   where (hot_attempted_at is null or hot_attempted_at<=now()-interval '5 minutes')
   group by source_id
  ) select s.id,d.ids from public.sources s join due d on d.source_id=s.id
   where s.hot_next_at<=now() and (s.lease_until is null or s.lease_until<now())
   order by s.hot_next_at,d.attempted nulls first,s.id
   limit least(greatest(batch_size,1),6) for update of s skip locked
 loop
  update public.sources set lease_until=now()+interval '3 minutes',lease_token=gen_random_uuid() where id=candidate.id returning * into src;
  ids:=candidate.ids;
  insert into public.hot_verification_runs(source_id,lease_token,offer_ids) values(src.id,src.lease_token,ids) returning id into job_id;
  update public.offers set hot_attempted_at=now() where id=any(ids);
  return next to_jsonb(src)||jsonb_build_object('hot_run_id',job_id,'hot_external_ids',(select jsonb_agg(external_id) from public.offers where id=any(ids)));
 end loop;
end $$;
create function public.complete_hot_verification(p_run_id uuid,p_lease_token uuid,p_offers jsonb,p_complete boolean,p_error text default null)
returns integer language plpgsql security invoker set search_path='' as $$
declare job public.hot_verification_runs; src public.sources; old public.offers; item jsonb; seen text[]:='{}'; verified integer:=0;
begin
 select * into job from public.hot_verification_runs where id=p_run_id for update;
 if job.id is null or job.finished_at is not null or p_lease_token is null or job.lease_token<>p_lease_token then raise exception 'verification lease expired'; end if;
 select * into src from public.sources where id=job.source_id for update;
 if src.lease_token is distinct from p_lease_token then raise exception 'verification lease expired'; end if;
 if p_error is null then
  for item in select value from jsonb_array_elements(p_offers) loop
   select * into old from public.offers where source_id=src.id and id=any(job.offer_ids) and external_id=item->>'external_id';
   if old.id is null then continue; end if;
   if old.external_id=any(seen) then continue; end if;
   update public.offers set price=(item->>'price')::numeric,currency=item->>'currency',stock_status=item->>'stock_status',
    raw_title=item->>'raw_title',platform=item->>'platform',plan=item->>'plan',delivery=item->>'delivery',
    duration_days=nullif(item->>'duration_days','')::integer,comparison_key=item->>'comparison_key',review_required=(item->>'review_required')::boolean,
    purchase_url=item->>'purchase_url',raw_data=coalesce(item->'raw_data','{}'),last_seen_at=now(),expires_at=now()+interval '15 minutes',hot_verified_at=now(),active=true
   where id=old.id;
   if old.price is distinct from (item->>'price')::numeric or old.currency is distinct from item->>'currency' or old.stock_status is distinct from item->>'stock_status' then
    insert into public.price_history(offer_id,price,currency,stock_status) values(old.id,(item->>'price')::numeric,item->>'currency',item->>'stock_status');
   end if;
   seen:=array_append(seen,old.external_id); verified:=verified+1;
  end loop;
  -- Missing from a partial result is not proof of removal.
  if p_complete then update public.offers set active=false,hot_verified_at=now() where id=any(job.offer_ids) and not(external_id=any(seen)); end if;
 end if;
 update public.sources set lease_until=null,lease_token=null,hot_next_at=now()+case when p_error is null then interval '5 minutes' else interval '30 minutes' end where id=src.id;
 update public.hot_verification_runs set finished_at=now(),status=case when p_error is null then 'success' else 'failed' end,verified_count=verified,error=left(p_error,1000) where id=job.id;
 delete from public.hot_verification_runs where started_at<now()-interval '3 days';
 return verified;
end $$;
revoke all on function public.claim_hot_sources(integer),public.complete_hot_verification(uuid,uuid,jsonb,boolean,text) from public,anon,authenticated;
grant execute on function public.claim_hot_sources(integer),public.complete_hot_verification(uuid,uuid,jsonb,boolean,text) to service_role;
