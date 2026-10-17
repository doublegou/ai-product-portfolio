create table public.sources (
 id uuid primary key default gen_random_uuid(), name text not null, base_url text not null,
 collector text not null check (collector in ('kami','dujiao','shopapi','json','html')),
 config jsonb not null default '{}', enabled boolean not null default true,
 interval_minutes integer not null default 60 check(interval_minutes between 15 and 10080),
 next_crawl_at timestamptz not null default now(), lease_until timestamptz, lease_token uuid,
 last_success_at timestamptz, last_error text, consecutive_failures integer not null default 0,
 created_at timestamptz not null default now(), unique(base_url)
);
create table public.offers (
 id uuid primary key default gen_random_uuid(), source_id uuid not null references public.sources(id),
 external_id text not null, raw_title text not null, platform text not null, plan text not null,
 delivery text not null, duration_days integer, comparison_key text, review_required boolean not null default true,
 price numeric(12,2) not null check(price > 0), currency text not null default 'CNY',
 stock_status text not null check(stock_status in ('in_stock','out_of_stock','unknown')),
 purchase_url text not null, raw_data jsonb not null default '{}',
 last_seen_at timestamptz not null default now(), expires_at timestamptz not null,
 active boolean not null default true, unique(source_id,external_id)
);
create table public.price_history (
 id bigint generated always as identity primary key, offer_id uuid not null references public.offers(id),
 price numeric(12,2) not null, currency text not null, stock_status text not null,
 observed_at timestamptz not null default now()
);
create table public.crawl_runs (
 id uuid primary key default gen_random_uuid(), source_id uuid not null references public.sources(id),
 started_at timestamptz not null default now(), finished_at timestamptz,
 status text not null default 'running', offer_count integer not null default 0,
 complete_snapshot boolean not null default false, error text
);
create index on public.sources(next_crawl_at) where enabled;
create index on public.offers(comparison_key,price) where active;
create index on public.price_history(offer_id,observed_at desc);
create index on public.crawl_runs(started_at desc);
alter table public.sources enable row level security;
alter table public.offers enable row level security;
alter table public.price_history enable row level security;
alter table public.crawl_runs enable row level security;
revoke all on public.sources,public.offers,public.price_history,public.crawl_runs from anon, authenticated;
grant all on public.sources,public.offers,public.price_history,public.crawl_runs to service_role;
grant usage,select on all sequences in schema public to service_role;

create function public.claim_sources(batch_size integer default 2, requested_id uuid default null)
returns setof public.sources language plpgsql security definer set search_path=public as $$
begin
 return query with candidates as (
 select id from sources where enabled and (lease_until is null or lease_until < now())
 and ((requested_id is null and next_crawl_at <= now()) or id=requested_id)
 order by next_crawl_at for update skip locked limit least(greatest(batch_size,1),2)
 ) update sources s set lease_until=now()+interval '10 minutes',lease_token=gen_random_uuid()
 from candidates c where s.id=c.id returning s.*;
end $$;

create function public.complete_crawl(p_source_id uuid,p_lease_token uuid,p_run_id uuid,p_offers jsonb,p_complete boolean,p_error text default null)
returns void language plpgsql security definer set search_path=public as $$
declare s sources; item jsonb; old offers; saved offers; seen text[] := '{}';
begin
 select * into s from sources where id=p_source_id for update;
 if s.lease_token is distinct from p_lease_token then raise exception 'lease expired'; end if;
 if p_error is null then
  for item in select value from jsonb_array_elements(p_offers) loop
   select * into old from offers where source_id=s.id and external_id=item->>'external_id';
   insert into offers(source_id,external_id,raw_title,platform,plan,delivery,duration_days,comparison_key,review_required,price,currency,stock_status,purchase_url,raw_data,expires_at)
   values(s.id,item->>'external_id',item->>'raw_title',item->>'platform',item->>'plan',item->>'delivery',nullif(item->>'duration_days','')::integer,item->>'comparison_key',(item->>'review_required')::boolean,(item->>'price')::numeric,item->>'currency',item->>'stock_status',item->>'purchase_url',coalesce(item->'raw_data','{}'),now()+greatest(interval '24 hours',s.interval_minutes*3*interval '1 minute'))
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
  next_crawl_at=now()+case when p_error is null then interval_minutes else least(1440,interval_minutes*power(2,least(consecutive_failures+1,4))::integer) end*interval '1 minute'
 where id=s.id;
 update crawl_runs set finished_at=now(),status=case when p_error is null then 'success' else 'failed' end,
  offer_count=jsonb_array_length(p_offers),complete_snapshot=p_complete,error=left(p_error,1000) where id=p_run_id and source_id=s.id;
end $$;
revoke all on function public.claim_sources(integer,uuid), public.complete_crawl(uuid,uuid,uuid,jsonb,boolean,text) from public,anon,authenticated;
grant execute on function public.claim_sources(integer,uuid), public.complete_crawl(uuid,uuid,uuid,jsonb,boolean,text) to service_role;
