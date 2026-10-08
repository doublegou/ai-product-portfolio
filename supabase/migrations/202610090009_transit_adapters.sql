-- Extend existing original-source collection to the verified public catalog formats.
alter table public.transit_sources drop constraint transit_sources_collector_check;
alter table public.transit_sources add constraint transit_sources_collector_check
 check(collector in ('transit','newapi','zivv','onehop','public_models'));
