-- This storefront serves products under /item/{id}; its old commodity route returns 404.
update public.sources
set config = coalesce(config, '{}'::jsonb) || '{"purchase_path":"/item/{id}"}'::jsonb
where base_url in ('https://store.codesky.qzz.io', 'https://store.codesky.qzz.io/')
  and collector = 'kami';

-- Correct existing quotes without changing price, stock, or collection timestamps.
update public.offers o
set purchase_url = 'https://store.codesky.qzz.io/item/' || o.external_id
from public.sources s
where o.source_id = s.id
  and s.base_url in ('https://store.codesky.qzz.io', 'https://store.codesky.qzz.io/')
  and o.external_id ~ '^[0-9]+$'
  and o.purchase_url = 'https://store.codesky.qzz.io/commodity?id=' || o.external_id;
