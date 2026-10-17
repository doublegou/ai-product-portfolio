-- These storefronts use /item/{id}; price collection uses a separate API.
update public.sources set config=coalesce(config,'{}'::jsonb)||'{"purchase_path":"/item/{id}"}'::jsonb
where rtrim(base_url,'/') in ('https://yufenggpt.com','https://fk.gptcz.cc','https://lianduang.com') and collector='kami';
update public.offers o set purchase_url=rtrim(s.base_url,'/')||'/item/'||o.external_id
from public.sources s where o.source_id=s.id
and rtrim(s.base_url,'/') in ('https://yufenggpt.com','https://fk.gptcz.cc','https://lianduang.com')
and o.external_id ~ '^[0-9]+$'
and o.purchase_url=rtrim(s.base_url,'/')||'/commodity?id='||o.external_id;
