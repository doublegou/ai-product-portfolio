alter table public.sources drop constraint sources_collector_check;
alter table public.sources add constraint sources_collector_check check (collector in ('kami','dujiao','shopapi','16688','json','html'));

create or replace function public.claim_sources(batch_size integer default 2, requested_id uuid default null)
returns setof public.sources language plpgsql security definer set search_path=public as $$
begin
 return query with candidates as (
 select id from sources where enabled and (lease_until is null or lease_until < now())
 and ((requested_id is null and next_crawl_at <= now()) or id=requested_id)
 order by next_crawl_at for update skip locked limit least(greatest(batch_size,1),8)
 ) update sources s set lease_until=now()+interval '10 minutes',lease_token=gen_random_uuid()
 from candidates c where s.id=c.id returning s.*;
end $$;
