-- User-requested removal. Preserve history but stop collection and public display.
update public.sources set enabled=false where rtrim(base_url,'/') in (
  'https://gpt.ybkjs.top', 'https://fk.ybkjs.top', 'https://shop.aictk.shop',
  'https://www.16688.com.cn/shop/S935156',
  'https://www.16688.com.cn/shop/S840665',
  'https://www.16688.com.cn/shop/S277039'
);
update public.offers o set active=false from public.sources s
where o.source_id=s.id and rtrim(s.base_url,'/') in (
  'https://gpt.ybkjs.top', 'https://fk.ybkjs.top', 'https://shop.aictk.shop',
  'https://www.16688.com.cn/shop/S935156',
  'https://www.16688.com.cn/shop/S840665',
  'https://www.16688.com.cn/shop/S277039'
);
update public.sources set config=coalesce(config,'{}'::jsonb)||
  jsonb_build_object('excluded_product_ids',
    coalesce(config->'excluded_product_ids','[]'::jsonb)||'["527"]'::jsonb)
where rtrim(base_url,'/')='https://ai666.id';
update public.offers o set active=false from public.sources s
where o.source_id=s.id and rtrim(s.base_url,'/')='https://ai666.id'
and o.external_id='527';
