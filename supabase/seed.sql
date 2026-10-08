-- Merchant configurations verified against original sites; provenance is recorded in docs/source-onboarding.md.
-- No prices or third-party aggregation snapshots are seeded.
insert into public.sources(name,base_url,collector,interval_minutes,config)
values
 ('AI智充','https://aicz.ink/','html',60,'{"path":"/","item_selector":".goods-card","title_selector":".goods-title","price_selector":".goods-price","link_selector":"a","full_snapshot":true}'),
 ('西瓜小铺','https://xigua.ink/','dujiao',60,'{}'),
 ('环球小铺','https://gospv.com/','dujiao',60,'{}'),
 ('AI能量小店','https://dimosky.com/','kami',60,'{}'),
 ('炼丹师小铺','https://lianduang.com/','kami',60,'{}'),
 ('V3小店','https://shop.gpt.ge/','html',60,'{"path":"/","item_selector":"a[href^=''/buy/'']","title_selector":"h3","price_selector":"strong","link_selector":"a","stock_selector":"p","currency":"CNY","full_snapshot":false,"stock_map":{"自动发货·库存 充足":"in_stock","自动发货·库存 一般":"in_stock","缺货·库存 无货":"out_of_stock"}}'),
 ('Aisou智充','https://aisou.pro/','kami',360,'{}'),
 ('T佬的gmail批发渠道','https://ai666.dnxb.cc/','kami',360,'{}'),
 ('Gemini账号批发douyiner.cn','https://douyiner.cn/','kami',360,'{}'),
 ('七叔数字社','https://ai666.id/','kami',360,'{}'),
 ('AI 会员代充，即买即用 - Florence AI','https://faka.redeemai.me/','kami',360,'{}'),
 ('86GameStore','https://faka.redeemgpt.com/','kami',360,'{}'),
 ('Goutou小铺','https://fk.gptcz.cc/','kami',360,'{}'),
 ('谷歌邮箱 AI源头批发','https://hiemail.store/','kami',360,'{}'),
 ('NikoCard','https://nikoers.com/','kami',360,'{}'),
 ('笔墨小铺-  专供GPT Claude Gemini相关羊毛','https://shop.bmoplus.com/','kami',360,'{}'),
 ('shopcardai.click','https://shopcardai.click/','kami',360,'{}'),
 ('异次元店铺','https://shihuiai.cn/','kami',360,'{}'),
 ('蔚莱云Ai出海跨境账号','https://web3chirou.com/','kami',360,'{}'),
 ('Wiki123 卡网','https://wiki123.top/','kami',360,'{}'),
 ('yh-mo源头批发','https://yh-mo.xyz/','kami',360,'{}'),
 ('ac-card.org','https://ac-card.org/','dujiao',360,'{}'),
 ('burstpro-ai.online','https://burstpro-ai.online/','dujiao',360,'{}'),
 ('ccdawang.win','https://ccdawang.win/','dujiao',360,'{}'),
 ('zhang520.store','https://zhang520.store/','dujiao',360,'{}'),
 ('AUTO FK','https://aifk.opensora.de/','html',360,'{"path":"/","item_selector":".card:has(a[href*=\"/buy/\"]):not(:contains(\"打赏\"))","title_selector":".card-title","price_selector":"strong","link_selector":"a[href*=\"/buy/\"]","stock_selector":".text-muted","stock_prefix":"库存：","full_snapshot":false}'),
 ('小黑丸','https://upgrade.xiaoheiwan.com/','html',360,'{"path":"/","item_selector":"a.xhw-product-card","title_selector":"h3","price_selector":".tabular-nums","link_selector":"a","stock_selector":"span:has(svg.lucide-circle-check-big)","stock_map":{"可购买":"in_stock"},"full_snapshot":false}')
on conflict(base_url) do nothing;

-- 2026-10-07: independently verified original 16688 storefronts (12-hour refresh).
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('蜘蛛侠AI代充源头','https://www.16688.com.cn/shop/S286366','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI源头(销量第一，可开发票，C.hat.gp.t /codex源头，有平台保障，可开发票）','https://www.16688.com.cn/shop/S686646','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('老杭AI海外源头','https://www.16688.com.cn/shop/S294947','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI批发站｜渠道供货｜自助下单','https://www.16688.com.cn/shop/S103573','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('大个儿---欢迎分销--对接：97dg','https://www.16688.com.cn/shop/S677698','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('山姆AI（源头直供，诚招代理）','https://www.16688.com.cn/shop/S572891','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI小墨','https://www.16688.com.cn/shop/S396961','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI海外账号','https://www.16688.com.cn/shop/S590223','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小鸟 ai','https://www.16688.com.cn/shop/S569657','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('ZH API','https://www.16688.com.cn/shop/S946133','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI奥特曼|代充源头招代理','https://www.16688.com.cn/shop/S205325','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('尼克的AI工具箱','https://www.16688.com.cn/shop/S133868','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Aqvyn Token超市','https://www.16688.com.cn/shop/S890464','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI咕咕嘎嘎【直充源头】','https://www.16688.com.cn/shop/S166169','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('弗莱彻AI','https://www.16688.com.cn/shop/S149240','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小久','https://www.16688.com.cn/shop/S974686','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Yuan','https://www.16688.com.cn/shop/S753205','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('gemini反重力源头','https://www.16688.com.cn/shop/S801630','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('【低倍中转站】【官方正价】充值','https://www.16688.com.cn/shop/S814032','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('肖恩的出海商城','https://www.16688.com.cn/shop/S539740','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('皮特小铺','https://www.16688.com.cn/shop/S231625','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('KK发卡网（千人大群售后有保障）','https://www.16688.com.cn/shop/S701018','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Ai充值','https://www.16688.com.cn/shop/S456099','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('老源头AI--可开发票可对公--量大谈价','https://www.16688.com.cn/shop/S332095','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('zb10000','https://www.16688.com.cn/shop/S191336','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('凌小创ai','https://www.16688.com.cn/shop/S402946','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('老白ai对接：SSS333','https://www.16688.com.cn/shop/S442331','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('3364901671','https://www.16688.com.cn/shop/S382980','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('鸭鸭小店','https://www.16688.com.cn/shop/S325198','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('王哈哈Ai','https://www.16688.com.cn/shop/S206803','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小林发卡','https://www.16688.com.cn/shop/S189351','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('杰哥AI订阅小铺','https://www.16688.com.cn/shop/S393570','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('52XUEAI-可开发票','https://www.16688.com.cn/shop/S937885','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('一米阳光','https://www.16688.com.cn/shop/S908105','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AIHub订阅批发站｜渠道供货｜自助下单(招代理）','https://www.16688.com.cn/shop/S580515','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI杂货铺','https://www.16688.com.cn/shop/S627299','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('sms688 对接QY688','https://www.16688.com.cn/shop/S799286','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('千俞','https://www.16688.com.cn/shop/S163607','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('奥特曼直销','https://www.16688.com.cn/shop/S802470','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AK老鬼','https://www.16688.com.cn/shop/S383922','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('气田','https://www.16688.com.cn/shop/S201135','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小魏Ai批发','https://www.16688.com.cn/shop/S618739','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('源点数字','https://www.16688.com.cn/shop/S396555','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('21℃','https://www.16688.com.cn/shop/S853492','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('NexusAI','https://www.16688.com.cn/shop/S274051','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('无界AI','https://www.16688.com.cn/shop/S277039','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('CIM 对接马CIMCIM','https://www.16688.com.cn/shop/S216476','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('源头Ai供应/招代理','https://www.16688.com.cn/shop/S122191','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('超梦ai【可开发票-注意看商品说明】','https://www.16688.com.cn/shop/S579520','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('北橘号铺-对接:DC260818VOY2Y7AD','https://www.16688.com.cn/shop/S605033','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('一苇的ai小铺','https://www.16688.com.cn/shop/S542868','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI源头供货商/招代理','https://www.16688.com.cn/shop/S840735','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('蜡笔小新','https://www.16688.com.cn/shop/S301515','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI哈哈小胖（诚招代理）','https://www.16688.com.cn/shop/S692020','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('天青优质','https://www.16688.com.cn/shop/S644467','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI会员代充拼车','https://www.16688.com.cn/shop/S738947','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('可可鸭AI小铺','https://www.16688.com.cn/shop/S195687','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Tl 菲区源头 诚招代理','https://www.16688.com.cn/shop/S497361','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('霜星的AI小店','https://www.16688.com.cn/shop/S248535','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('jz的店','https://www.16688.com.cn/shop/S778259','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('鸡皮踢 全网最权威渠道','https://www.16688.com.cn/shop/S120607','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI充值','https://www.16688.com.cn/shop/S361816','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('旺旺小铺','https://www.16688.com.cn/shop/S609525','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('雷动九天','https://www.16688.com.cn/shop/S113713','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('一梦AI货源 招代理 对接马yimeng','https://www.16688.com.cn/shop/S104052','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('痞老板Ai批发 招代理','https://www.16688.com.cn/shop/S584292','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('海螺AI服务','https://www.16688.com.cn/shop/S688779','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('101科技','https://www.16688.com.cn/shop/S331133','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('派大星（2500人群售后无忧）对接马 HARVEY','https://www.16688.com.cn/shop/S343514','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('2127487507','https://www.16688.com.cn/shop/S949752','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Tcc谷歌邮箱批发-【招代理】','https://www.16688.com.cn/shop/S689928','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小少','https://www.16688.com.cn/shop/S226302','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI team的神','https://www.16688.com.cn/shop/S454961','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('阿库娅ai源头','https://www.16688.com.cn/shop/S703125','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小勇同学','https://www.16688.com.cn/shop/S335399','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('KFC卡网🍟可开发票  源头AI稳定供应','https://www.16688.com.cn/shop/S311799','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('铃铛的AI小铺','https://www.16688.com.cn/shop/S721790','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('花若的小铺子','https://www.16688.com.cn/shop/S462029','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('啊富','https://www.16688.com.cn/shop/S626428','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('domi卡密专供','https://www.16688.com.cn/shop/S855961','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小店','https://www.16688.com.cn/shop/S935156','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('CodexTool-对接：CODEXTOOL','https://www.16688.com.cn/shop/S909910','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('2705609672','https://www.16688.com.cn/shop/S391421','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('海帆科技','https://www.16688.com.cn/shop/S295083','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('格洛克Ai（招代理 对接马G-ROK888）','https://www.16688.com.cn/shop/S158155','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('落雪AI','https://www.16688.com.cn/shop/S325514','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('人民的AI','https://www.16688.com.cn/shop/S584797','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('前进四','https://www.16688.com.cn/shop/S581509','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('壹号铺','https://www.16688.com.cn/shop/S962873','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('浅梦杂货铺','https://www.16688.com.cn/shop/S301156','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('葡萄Ai小铺','https://www.16688.com.cn/shop/S194067','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('源头AI - Bot | 对接：team','https://www.16688.com.cn/shop/S513295','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('樱花AI小店 对接马 ：YINGHUA','https://www.16688.com.cn/shop/S492597','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI卡网小铺','https://www.16688.com.cn/shop/S356374','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小白AI订阅源头--对接 XIAOBAI','https://www.16688.com.cn/shop/S678924','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('嘿嘿小店','https://www.16688.com.cn/shop/S115731','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI效率工坊','https://www.16688.com.cn/shop/S177627','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('QX店铺 - 源头ai - 对接：QINXI','https://www.16688.com.cn/shop/S366907','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Candy小铺','https://www.16688.com.cn/shop/S765071','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('阿秋AI','https://www.16688.com.cn/shop/S899766','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('华润','https://www.16688.com.cn/shop/S552918','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Xai 大玩家','https://www.16688.com.cn/shop/S103032','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('冷热lab','https://www.16688.com.cn/shop/S424005','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('智能的mee','https://www.16688.com.cn/shop/S249990','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('ai跑起来','https://www.16688.com.cn/shop/S704668','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('全球云充AI旗舰服务','https://www.16688.com.cn/shop/S928966','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('若依的小铺','https://www.16688.com.cn/shop/S639222','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小飞AI服务代理站','https://www.16688.com.cn/shop/S703574','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI集合铺','https://www.16688.com.cn/shop/S677320','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('卡卡大魔王','https://www.16688.com.cn/shop/S969433','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('齊AI','https://www.16688.com.cn/shop/S329295','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('勇闯AI','https://www.16688.com.cn/shop/S603222','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AGI充值平台','https://www.16688.com.cn/shop/S133580','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('蓝博ai','https://www.16688.com.cn/shop/S683508','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小小杂货铺','https://www.16688.com.cn/shop/S571979','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI批发','https://www.16688.com.cn/shop/S526627','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI-TECH-STORE','https://www.16688.com.cn/shop/S417643','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI小狗代充','https://www.16688.com.cn/shop/S894156','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AITOP','https://www.16688.com.cn/shop/S358448','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('希思罗AI','https://www.16688.com.cn/shop/S872517','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('柯炀网络','https://www.16688.com.cn/shop/S221796','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('绘梦小铺','https://www.16688.com.cn/shop/S318404','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('带鱼ai','https://www.16688.com.cn/shop/S888822','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('juenjay1','https://www.16688.com.cn/shop/S253058','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('SIMON的AI小铺','https://www.16688.com.cn/shop/S741986','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('BigbananaAI','https://www.16688.com.cn/shop/S966321','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('liuyuxiangzzz','https://www.16688.com.cn/shop/S750592','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('知悦科技','https://www.16688.com.cn/shop/S100773','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('墨小云Token商店','https://www.16688.com.cn/shop/S865638','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('凌越穹顶源头招代理','https://www.16688.com.cn/shop/S230844','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Ai猫','https://www.16688.com.cn/shop/S199223','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('东东大王','https://www.16688.com.cn/shop/S375979','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('柠檬茶的小铺','https://www.16688.com.cn/shop/S480340','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI零度','https://www.16688.com.cn/shop/S645138','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小乐Ai','https://www.16688.com.cn/shop/S463855','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('办办ai','https://www.16688.com.cn/shop/S803935','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('奶龙Gemini订阅(源头招代理)','https://www.16688.com.cn/shop/S323867','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('喵喵ai','https://www.16688.com.cn/shop/S301395','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AAA批发多儿王哥','https://www.16688.com.cn/shop/S587901','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小K源头','https://www.16688.com.cn/shop/S390418','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('自营 AI 小铺接马源头','https://www.16688.com.cn/shop/S156171','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('1225069983','https://www.16688.com.cn/shop/S677335','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('带鱼 Ai 代理对接：chongpro','https://www.16688.com.cn/shop/S402690','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('千云科技','https://www.16688.com.cn/shop/S689386','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('wenqi168168168','https://www.16688.com.cn/shop/S349849','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Gemini18月链接专卖','https://www.16688.com.cn/shop/S396009','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小黑Ai【招代理】','https://www.16688.com.cn/shop/S165628','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('1159165373','https://www.16688.com.cn/shop/S415348','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('启元Ai','https://www.16688.com.cn/shop/S170365','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Po1nt9','https://www.16688.com.cn/shop/S316019','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小店','https://www.16688.com.cn/shop/S797217','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('派大星Ai','https://www.16688.com.cn/shop/S305111','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('智充云卡','https://www.16688.com.cn/shop/S423370','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小高老板娘的店','https://www.16688.com.cn/shop/S763680','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Kris的AI资源站','https://www.16688.com.cn/shop/S807784','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('1452948271','https://www.16688.com.cn/shop/S802198','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('圆梦AI','https://www.16688.com.cn/shop/S123284','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('大牛Ai集合站','https://www.16688.com.cn/shop/S737485','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI充值小铺','https://www.16688.com.cn/shop/S588147','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('与世无争的AI小店','https://www.16688.com.cn/shop/S649528','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Ai家族（分）','https://www.16688.com.cn/shop/S147808','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('智云AI','https://www.16688.com.cn/shop/S719990','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('桃子的Ai小店','https://www.16688.com.cn/shop/S732628','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('2898039401','https://www.16688.com.cn/shop/S170432','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('寰宇订阅｜全球 AI 会员订阅服务','https://www.16688.com.cn/shop/S402092','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('猪猪侠ai','https://www.16688.com.cn/shop/S557565','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('正版Ai服务站','https://www.16688.com.cn/shop/S698830','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('北海AI','https://www.16688.com.cn/shop/S935459','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('YOYO云','https://www.16688.com.cn/shop/S235580','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI中转仓','https://www.16688.com.cn/shop/S841629','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI客栈','https://www.16688.com.cn/shop/S981664','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('gmd','https://www.16688.com.cn/shop/S500101','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI源头','https://www.16688.com.cn/shop/S654368','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小鑫店铺','https://www.16688.com.cn/shop/S479033','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('1312237960','https://www.16688.com.cn/shop/S228858','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('mobais','https://www.16688.com.cn/shop/S672828','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('阮旭东.Al','https://www.16688.com.cn/shop/S366726','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI优速通','https://www.16688.com.cn/shop/S790173','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI风控大王','https://www.16688.com.cn/shop/S558218','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('ton','https://www.16688.com.cn/shop/S136056','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Pp小店','https://www.16688.com.cn/shop/S543798','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('青山AI小店','https://www.16688.com.cn/shop/S821109','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('云吞小卖部','https://www.16688.com.cn/shop/S472977','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('临期plus小店','https://www.16688.com.cn/shop/S265669','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI练习生','https://www.16688.com.cn/shop/S943903','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Codex 验证小铺','https://www.16688.com.cn/shop/S721127','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('Esfine','https://www.16688.com.cn/shop/S409622','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('jackbao','https://www.16688.com.cn/shop/S508814','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('伯牙AI','https://www.16688.com.cn/shop/S379897','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('7237846','https://www.16688.com.cn/shop/S358946','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('咕咕鸡｜蓝V代充','https://www.16688.com.cn/shop/S717642','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('赛博小铺','https://www.16688.com.cn/shop/S118330','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('ly13203696568','https://www.16688.com.cn/shop/S571041','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('xl百货店','https://www.16688.com.cn/shop/S223903','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('望月代充小店','https://www.16688.com.cn/shop/S725296','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('方糖AI','https://www.16688.com.cn/shop/S439808','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('方脸','https://www.16688.com.cn/shop/S851838','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('岚 源头批发 支持对公、开票','https://www.16688.com.cn/shop/S388414','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('骆伯秋','https://www.16688.com.cn/shop/S295983','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('全域 AI 克劳德','https://www.16688.com.cn/shop/S557522','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('小庄 AI 会员订阅服务','https://www.16688.com.cn/shop/S176014','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI_云顶👑【源头认证】','https://www.16688.com.cn/shop/S957347','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('蛋AI🔥','https://www.16688.com.cn/shop/S476976','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('橘子Ai源头','https://www.16688.com.cn/shop/S126330','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('齊AI','https://www.16688.com.cn/shop/S162108','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AI源头（招代理，可开发票）','https://www.16688.com.cn/shop/S332568','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('AIAuto','https://www.16688.com.cn/shop/S372381','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('vvv988','https://www.16688.com.cn/shop/S608038','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
insert into public.sources (name,base_url,collector,interval_minutes,config) values ('梦泽Ai','https://www.16688.com.cn/shop/S528762','16688',720,'{}'::jsonb) on conflict (base_url) do nothing;
