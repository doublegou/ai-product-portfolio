-- Read-only check: persisted configured routes must match every active numeric SKU.
do $$
begin
 if exists (
  select 1 from public.offers o join public.sources s on s.id=o.source_id
  where s.enabled and o.active and s.collector='kami'
  and s.config->>'purchase_path'='/item/{id}' and o.external_id ~ '^[0-9]+$'
  and o.purchase_url is distinct from rtrim(s.base_url,'/')||'/item/'||o.external_id
 ) then raise exception 'Persisted purchase route does not match configured storefront'; end if;
end $$;
