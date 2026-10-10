-- Run with: npx supabase db query --linked --file tests/incremental-database.sql
-- All fixtures and policy changes roll back, including simulated heat.
begin;
do $$
declare a jsonb; b jsonb; saved jsonb; source_id uuid; merchant text;
begin
 if has_function_privilege('anon','public.export_snapshot_batch(boolean)','execute')
    or has_function_privilege('authenticated','public.apply_collection_heat(jsonb)','execute') then
  raise exception 'Private RPC exposed';
 end if;
 if exists(select 1 from pg_class where oid in ('public.snapshot_export_state'::regclass,'public.snapshot_export_entities'::regclass,'public.collection_heat_state'::regclass) and not relrowsecurity) then
  raise exception 'Private state missing RLS';
 end if;
 a:=public.snapshot_json_diff('{"prices":[{"price":1}],"removed":true}'::jsonb,'{"prices":[{"price":2}],"added":3}'::jsonb);
 if jsonb_array_length(a)<>3 then raise exception 'Nested diff missed changes'; end if;
 -- Avoid rebuilding the real dataset: a pending batch is the retry path.
 select jsonb_build_object('schema',1,'revision',revision+1,'base_revision',revision,'full',false,'generated_at',now(),'changes','[]'::jsonb) into saved from public.snapshot_export_state where id for update;
 update public.snapshot_export_state set pending=saved,budget_day=current_date,sent_bytes=40000000 where id;
 a:=public.export_snapshot_batch();
 b:=public.export_snapshot_batch();
 if not (a->>'budget_exhausted')::boolean or a<>b or (select pending from public.snapshot_export_state where id)<>saved then
  raise exception 'Budget pause lost pending batch';
 end if;
 update public.snapshot_export_state set budget_day=current_date-1 where id;
 a:=public.export_snapshot_batch();
 if a<>saved or (select sent_bytes from public.snapshot_export_state where id)<>octet_length(saved::text) then
  raise exception 'Next-day resume changed batch or accounting';
 end if;
 select s.id,public.merchant_analytics_id(s.base_url) into source_id,merchant from public.sources s where enabled and adaptive_enabled limit 1;
 if source_id is null then raise exception 'No adaptive source fixture'; end if;
 update public.sources set consecutive_failures=0,interval_minutes=60,collection_tier='normal' where id=source_id;
 update public.collection_heat_state set generated_at=null,last_applied_at=now(),sources='[]' where id;
 perform public.apply_collection_heat(jsonb_build_object('generated_at',now(),'sources',jsonb_build_array(jsonb_build_object('id',merchant,'clicks',3))));
 if not exists(select 1 from public.sources where id=source_id and interval_minutes=10 and collection_tier='hot') then
  raise exception 'First fresh heat did not immediately accelerate source';
 end if;
 if (select count(*) from public.sources where enabled and adaptive_enabled and collection_tier='hot')>20 then raise exception 'Hot-source cap exceeded'; end if;
 update public.sources set adaptive_enabled=false,interval_minutes=77 where id=source_id;
 update public.collection_heat_state set last_applied_at=now()-interval '2 hours' where id;
 perform public.apply_collection_heat();
 if (select interval_minutes from public.sources where id=source_id)<>77 then raise exception 'Manual interval overwritten'; end if;
end $$;
rollback;
