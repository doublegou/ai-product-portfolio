-- Routes verified against storefront controllers or the actual product identifier.
create temporary table verified_purchase_hosts (url text primary key) on commit drop;
insert into verified_purchase_hosts values
 ('https://ai666.dnxb.cc'),
 ('https://ai666.id'),
 ('https://aichongz.cc'),
 ('https://aisou.pro'),
 ('https://dimosky.com'),
 ('https://faka.bbanai.site'),
 ('https://faka.redeemai.me'),
 ('https://faka.redeemgpt.com'),
 ('https://fk.10886.xyz'),
 ('https://gmailsol.com'),
 ('https://google7676.top'),
 ('https://hiemail.store'),
 ('https://kbshub.store'),
 ('https://nikoers.com'),
 ('https://shop.bmoplus.com'),
 ('https://shop.sunnydolls.dpdns.org'),
 ('https://shopcardai.click'),
 ('https://web3chirou.com'),
 ('https://wiki123.top'),
 ('https://yh-mo.xyz');
update public.sources s set config=coalesce(config,'{}'::jsonb)||'{"purchase_path":"/item/{id}"}'::jsonb
where rtrim(s.base_url,'/') in (select url from verified_purchase_hosts) and collector='kami';
update public.offers o set purchase_url=rtrim(s.base_url,'/')||'/item/'||o.external_id
from public.sources s where o.source_id=s.id
and rtrim(s.base_url,'/') in (select url from verified_purchase_hosts)
and o.external_id ~ '^[0-9]+$'
and o.purchase_url=rtrim(s.base_url,'/')||'/commodity?id='||o.external_id;
