-- ShopGPT uses /item/{id}; the legacy /commodity?id={id} route returns 404.
update public.sources
set config = coalesce(config, '{}'::jsonb) || '{"purchase_path":"/item/{id}"}'::jsonb
where base_url in ('https://shopgpt.plus', 'https://shopgpt.plus/')
  and collector = 'kami';

update public.offers o
set purchase_url = 'https://shopgpt.plus/item/' || o.external_id
from public.sources s
where o.source_id = s.id
  and s.base_url in ('https://shopgpt.plus', 'https://shopgpt.plus/')
  and o.external_id ~ '^[0-9]+$'
  and o.purchase_url = 'https://shopgpt.plus/commodity?id=' || o.external_id;
