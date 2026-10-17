-- Send visitors to AI智充's own landing page as requested, rather than its external checkout.
update public.sources
set config = coalesce(config, '{}'::jsonb) || '{"purchase_path":"/"}'::jsonb
where base_url in ('https://aicz.ink', 'https://aicz.ink/')
  and collector = 'html';

update public.offers o
set purchase_url = 'https://aicz.ink/'
from public.sources s
where o.source_id = s.id
  and s.base_url in ('https://aicz.ink', 'https://aicz.ink/')
  and o.purchase_url is distinct from 'https://aicz.ink/';
