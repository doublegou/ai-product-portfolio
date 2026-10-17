-- Original API relay prices are isolated from card/subscription offers.
create table public.transit_sources (
 id text primary key default gen_random_uuid()::text check (id ~ '^[a-z0-9-]{1,100}$'),
 name text not null check(length(name) between 1 and 100),
 base_url text not null unique, collector text not null check(collector in ('transit','newapi')),
 config jsonb not null default '{}', enabled boolean not null default true,
 interval_minutes integer not null default 15 check(interval_minutes between 15 and 10080),
 next_crawl_at timestamptz not null default now(), last_success_at timestamptz, last_error text,
 failure_count integer not null default 0, lease_token uuid, lease_until timestamptz,
 created_at timestamptz not null default now()
);
create table public.transit_snapshots (
 source_id text primary key references public.transit_sources(id) on delete cascade,
 data jsonb not null check(jsonb_typeof(data)='object'),
 quote_count integer not null check(quote_count between 1 and 5000),
 last_seen_at timestamptz not null, expires_at timestamptz not null
);
create table public.transit_crawl_runs (
 id uuid primary key default gen_random_uuid(),
 source_id text not null references public.transit_sources(id) on delete cascade,
 started_at timestamptz not null default now(), finished_at timestamptz,
 status text not null default 'running' check(status in ('running','success','failed')),
 offer_count integer not null default 0, error text
);
create index on public.transit_sources(next_crawl_at) where enabled;
create index on public.transit_crawl_runs(started_at desc);
alter table public.transit_sources enable row level security;
alter table public.transit_snapshots enable row level security;
alter table public.transit_crawl_runs enable row level security;
revoke all on public.transit_sources, public.transit_snapshots, public.transit_crawl_runs from public, anon, authenticated;
grant select,insert,update,delete on public.transit_sources, public.transit_snapshots, public.transit_crawl_runs to service_role;

create function public.claim_transit_sources(batch_size integer default 4, requested_id text default null)
returns setof public.transit_sources language plpgsql security invoker set search_path='' as $$
begin
 update public.transit_crawl_runs r set status='failed',finished_at=now(),error='上次任务超时，等待重试'
 from public.transit_sources s where r.source_id=s.id and r.status='running'
 and r.started_at<now()-interval '3 minutes' and coalesce(s.lease_until,now())<=now();
 return query with selected as (
  select s.id from public.transit_sources s where s.enabled and (s.lease_until is null or s.lease_until<now())
  and ((requested_id is not null and s.id=requested_id) or (requested_id is null and s.next_crawl_at<=now()))
  order by s.next_crawl_at,s.id limit greatest(1,least(batch_size,8)) for update skip locked
 ) update public.transit_sources s set lease_token=gen_random_uuid(),lease_until=now()+interval '3 minutes'
 from selected x where s.id=x.id returning s.*;
end $$;
create function public.complete_transit_crawl(p_source_id text,p_lease_token uuid,p_run_id uuid,p_snapshot jsonb default null,p_error text default null)
returns void language plpgsql security invoker set search_path='' as $$
declare s public.transit_sources; n integer; seen timestamptz:=clock_timestamp();
begin
 select * into s from public.transit_sources where id=p_source_id for update;
 if s.lease_token is distinct from p_lease_token or p_lease_token is null or s.lease_until<now() then raise exception '采集租约已失效'; end if;
 if not exists(select 1 from public.transit_crawl_runs where id=p_run_id and source_id=p_source_id and status='running') then raise exception '采集记录不匹配'; end if;
 if p_error is not null then
  update public.transit_sources set last_error=left(p_error,1500),failure_count=failure_count+1,
   next_crawl_at=seen+make_interval(mins=>least(240,30*power(2,least(failure_count,3))::integer)),lease_until=null,lease_token=null where id=s.id;
  update public.transit_crawl_runs set status='failed',finished_at=seen,error=left(p_error,1500) where id=p_run_id;
  return;
 end if;
 if p_snapshot is null or jsonb_typeof(p_snapshot->'prices') is distinct from 'array' or p_snapshot->>'id' is distinct from s.id then raise exception '无效报价快照'; end if;
 n:=jsonb_array_length(p_snapshot->'prices');
 if n<1 or n>5000 or octet_length(p_snapshot::text)>8000000 then raise exception '报价快照大小异常'; end if;
 insert into public.transit_snapshots(source_id,data,quote_count,last_seen_at,expires_at)
 values(s.id,p_snapshot,n,seen,seen+make_interval(mins=>greatest(45,s.interval_minutes*3)))
 on conflict(source_id) do update set data=excluded.data,quote_count=excluded.quote_count,last_seen_at=excluded.last_seen_at,expires_at=excluded.expires_at;
 update public.transit_sources set last_success_at=seen,last_error=null,failure_count=0,
 next_crawl_at=seen+make_interval(mins=>interval_minutes),lease_until=null,lease_token=null where id=s.id;
 update public.transit_crawl_runs set status='success',finished_at=seen,offer_count=n,error=null where id=p_run_id;
end $$;
-- Return only public fields; the Worker streams this response without parsing large snapshots.
create function public.transit_page(p_limit integer default 2,p_offset integer default 0)
returns jsonb language sql stable security invoker set search_path='' as $$
 with visible as (select p.source_id,p.data,p.last_seen_at,p.expires_at,(s.last_error is not null) as collection_error
  from public.transit_snapshots p join public.transit_sources s on s.id=p.source_id where s.enabled),
 page as (select * from visible order by source_id limit greatest(1,least(p_limit,2)) offset greatest(0,p_offset)),
 totals as(select count(*)::integer as n from visible)
 select jsonb_build_object('stations',coalesce((select jsonb_agg(to_jsonb(page) order by source_id) from page),'[]'::jsonb),
 'total',n,'next_offset',case when p_offset+p_limit<n then p_offset+p_limit else null end) from totals;
$$;
revoke all on function public.claim_transit_sources(integer,text),public.complete_transit_crawl(text,uuid,uuid,jsonb,text),public.transit_page(integer,integer) from public,anon,authenticated;
grant execute on function public.claim_transit_sources(integer,text),public.complete_transit_crawl(text,uuid,uuid,jsonb,text),public.transit_page(integer,integer) to service_role;
