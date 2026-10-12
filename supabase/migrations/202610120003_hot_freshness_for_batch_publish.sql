-- Keep verified stock valid through a thirty-minute publication interval.
create or replace function public.complete_hot_verification(p_run_id uuid,p_lease_token uuid,p_offers jsonb,p_complete boolean,p_error text default null)
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
    purchase_url=item->>'purchase_url',raw_data=coalesce(item->'raw_data','{}'),last_seen_at=now(),expires_at=now()+interval '45 minutes',hot_verified_at=now(),active=true
   where id=old.id;
   if old.price is distinct from (item->>'price')::numeric or old.currency is distinct from item->>'currency' or old.stock_status is distinct from item->>'stock_status' then
    insert into public.price_history(offer_id,price,currency,stock_status) values(old.id,(item->>'price')::numeric,item->>'currency',item->>'stock_status');
   end if;
   seen:=array_append(seen,old.external_id); verified:=verified+1;
  end loop;
  -- Missing from a partial result is not proof of removal.
  if p_complete then update public.offers set active=false,hot_verified_at=now() where id=any(job.offer_ids) and not(external_id=any(seen)); end if;
 end if;
 update public.sources set hot_last_success_at=case when p_error is null then now() else hot_last_success_at end,hot_last_error=left(p_error,1000),hot_verified_count=verified,lease_until=null,lease_token=null,hot_next_at=now()+case when p_error is null then interval '5 minutes' else interval '30 minutes' end where id=src.id;
 update public.hot_verification_runs set finished_at=now(),status=case when p_error is null then 'success' else 'failed' end,verified_count=verified,error=left(p_error,1000) where id=job.id;
 delete from public.hot_verification_runs where started_at<now()-interval '3 days';
 return verified;
end $$;
