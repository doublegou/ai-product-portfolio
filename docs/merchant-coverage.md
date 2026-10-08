# 卡网商家覆盖核验 · 2026-10-09

核验时间：2026-10-08T20:08:55.058Z。参考：[PriceAI 商家目录](https://priceai.cc/channels?view=merchants)。只提取名称、地址、接口类型作为核验线索；所有价格与库存均由原站采集器读取，未导入 PriceAI 报价。

## 数量口径

| 项目 | 数量 |
| --- | ---: |
| PriceAI 目录记录 | 699 |
| 能按完整店铺地址识别、去重的参考地址 | 664 |
| 没有可识别地址的记录 | 32 |
| 重复地址记录 | 3 |
| 本次之前登记来源 | 236 |
| 原来与参考地址重合 | 218 |
| 原来缺少的参考地址 | 446 |
| 本次新增、通过原站试采集 | 138 |
| 经原站确认是已有店铺的地址别名 | 2 |
| 现在登记来源 | 374 |
| 已对应上的参考地址（含别名） | 358 |
| 仍未接通的参考地址 | 306 |

这里按店铺地址计数，同一商家可能在不同平台开店；不能直接等同于独立经营者人数。原先的 18 个“本站额外地址”中有 2 个被确认是参考目录中的别名，剩余 16 个仍保留自己的原站采集。

“已登记／通过试采集”不等于此刻每家都采集成功。新接入的 8 家 wzyp 商铺在本地试采成功，云端随后遇到验证页；其余同平台大量地址遇到 520。数据库保留每次失败原因，未生成假报价，也未绕过验证页或 robots 规则。

## 更新与库存

原先 6 家／21 家／209 家是三批导入配置：60／360／720 分钟，并非产品能力要求。本次所有启用来源统一设为 15 分钟；Cloudflare 每分钟调用 Supabase 采集函数，一批最多领取 64 家，4 家并发。同一原站的请求至少错开 500 毫秒；遇到 429、502、503、520，本轮暂停继续请求该域名。

15 分钟是正常来源的目标周期，从上次采集完成后计时；排队和网络耗时会带来偏差。失败按 30／60／120／240 分钟退避，45 分钟未确认的报价显示过期，不再参与最低价。前端每 5 分钟读取数据库，打开或重新聚焦时立即读取；采集确认时间始终使用 last_seen_at。

库存现在分为原站明确公布的件数、原站的定性文字（如“库存很多”“库存充足”）、有货但未公布数量、未公布库存、缺货及待更新。隐藏具体数量的 ShopApi 商品仅展示其官网采用的文字档位。商品级总库存不重复分配给每个 SKU。数据库通过 offers.raw_data 保存 stock_quantity / stock_text，API 映射至前端字段。

## 新增来源

| 名称 | 原站地址 | 结果 |
| --- | --- | --- |
| FF01 | https://www.16688.com.cn/shop/S687067 | 4 条原站报价 |
| Gemini源头供货商 | https://wzyp.cn/shop/pixelshop | 11 条原站报价 |
| Moming AI | https://www.16688.com.cn/shop/S532328 | 2 条原站报价 |
| CDK668（源头出货，可开发票，有量有价，欢迎代理对接） | https://www.16688.com.cn/shop/S855142 | 4 条原站报价 |
| TOPSTAR | https://wzyp.cn/shop/COQNA6PX | 7 条原站报价 |
| openai官方 | https://www.16688.com.cn/shop/S274389 | 6 条原站报价 |
| 千羽ai批发 | https://www.16688.com.cn/shop/S358780 | 6 条原站报价 |
| sms688🔥对接码qy688 | https://wzyp.cn/shop/OCBP9CJZ | 19 条原站报价 |
| 与世隔绝的AI小店 | https://wzyp.cn/shop/luoerl | 68 条原站报价 |
| 优质AI科技 | https://wzyp.cn/shop/youzhi | 212 条原站报价 |
| 02Nova（Gtp出货 可开发票 源头直供） | https://www.16688.com.cn/shop/S881067 | 4 条原站报价 |
| Fkai-Plus Pro源头直供【招代理】 | https://wzyp.cn/shop/subaicc | 21 条原站报价 |
| AI海外账号 | https://wzyp.cn/shop/0000 | 24 条原站报价 |
| 直连AI | https://wzyp.cn/shop/3GYP7PKO | 88 条原站报价 |
| 柴犬 AI | https://www.16688.com.cn/shop/S591295 | 4 条原站报价 |
| 狗ai | https://www.16688.com.cn/shop/S114445 | 4 条原站报价 |
| SkyAI源头---欢迎分销---对接：AI166888 | https://www.16688.com.cn/shop/S598150 | 4 条原站报价 |
| 口粮Mail | https://www.16688.com.cn/shop/S644276 | 2 条原站报价 |
| 66AI小铺 | https://www.16688.com.cn/shop/S134923 | 2 条原站报价 |
| AI批发商（全网底价）（低价走量） | https://www.16688.com.cn/shop/S315247 | 4 条原站报价 |
| 2632036440 | https://www.16688.com.cn/shop/S261171 | 7 条原站报价 |
| 杂货铺 | https://www.16688.com.cn/shop/S235521 | 7 条原站报价 |
| kuala | https://www.16688.com.cn/shop/S610658 | 5 条原站报价 |
| 低价稳定源头（招代理） | https://www.16688.com.cn/shop/S878919 | 6 条原站报价 |
| ai聚合--分销码 ADEFAI | https://www.16688.com.cn/shop/S981603 | 56 条原站报价 |
| 以太 AI服务订阅充值 | https://google7676.top | 17 条原站报价 |
| 91TOPGO | https://www.16688.com.cn/shop/S159512 | 7 条原站报价 |
| 唛选ai（可以开发票） | https://www.16688.com.cn/shop/S965521 | 3 条原站报价 |
| 灰灰的小铺 | https://www.16688.com.cn/shop/S265995 | 5 条原站报价 |
| 屿风ai-可开发票-注意看商品说明 | https://www.16688.com.cn/shop/S755531 | 7 条原站报价 |
| 良心小铺 | https://www.16688.com.cn/shop/S307788 | 8 条原站报价 |
| AI小店 | https://www.16688.com.cn/shop/S485596 | 3 条原站报价 |
| 会员直充 | https://www.16688.com.cn/shop/S981397 | 6 条原站报价 |
| GiPiTa 菲区源头 诚招代理 | https://www.16688.com.cn/shop/S848708 | 8 条原站报价 |
| CallAI | https://www.16688.com.cn/shop/S161857 | 4 条原站报价 |
| 小熊AI充值 | https://aichongz.cc | 13 条原站报价 |
| mymxhbyf888 | https://www.16688.com.cn/shop/S714081 | 1 条原站报价 |
| 福利吧 | https://www.16688.com.cn/shop/S559923 | 11 条原站报价 |
| 蜗牛小店 | https://www.16688.com.cn/shop/S644029 | 5 条原站报价 |
| 星宝小店 | https://xingbao-ai.shop | 已按原站页面/接口完成映射 |
| 兔子AI百宝箱 | https://www.16688.com.cn/shop/S603736 | 18 条原站报价 |
| 月饼店铺 | https://fk.ybkjs.top | 58 条原站报价 |
| 诺亚的AI小铺 | https://www.16688.com.cn/shop/S461375 | 4 条原站报价 |
| ai教父 | https://www.16688.com.cn/shop/S856265 | 4 条原站报价 |
| 555AI | https://www.16688.com.cn/shop/S412469 | 5 条原站报价 |
| BBAI 官方充值 | https://faka.bbanai.site | 11 条原站报价 |
| 乐易 | https://www.16688.com.cn/shop/S217110 | 9 条原站报价 |
| 云境AI | https://www.16688.com.cn/shop/S263233 | 9 条原站报价 |
| lyc1205159369 | https://www.16688.com.cn/shop/S629329 | 1 条原站报价 |
| wensiyaya | https://www.16688.com.cn/shop/S409411 | 1 条原站报价 |
| G屁T&Claude | https://www.16688.com.cn/shop/S829385 | 2 条原站报价 |
| 小小小铺 | https://www.16688.com.cn/shop/S926319 | 4 条原站报价 |
| 剑心AI小铺GiPiTa | https://www.16688.com.cn/shop/S785267 | 4 条原站报价 |
| edu邮箱 | https://www.16688.com.cn/shop/S975721 | 7 条原站报价 |
| 小月 Gro​k 质保专营店 | https://www.16688.com.cn/shop/S848121 | 7 条原站报价 |
| AI源头代充 | https://www.16688.com.cn/shop/S945852 | 11 条原站报价 |
| AI-Tibo-LLDCard（代理对接：TIBO666） | https://www.16688.com.cn/shop/S247817 | 4 条原站报价 |
| Justzqzb | https://www.16688.com.cn/shop/S390435 | 5 条原站报价 |
| 御風AI | https://yufenggpt.com | 12 条原站报价 |
| 人机验证 | https://kbshub.store | 6 条原站报价 |
| Xai代充 | https://www.16688.com.cn/shop/S686765 | 7 条原站报价 |
| 10886源头发卡网 | https://fk.10886.xyz | 14 条原站报价 |
| TFENG AI | https://www.16688.com.cn/shop/S566569 | 4 条原站报价 |
| 像素 AI 工具馆 | https://www.16688.com.cn/shop/S538681 | 9 条原站报价 |
| 时雨商城 | https://www.16688.com.cn/shop/S9527 | 1 条原站报价 |
| 星链阁 | https://www.16688.com.cn/shop/S193033 | 2 条原站报价 |
| 天空之上 | https://www.16688.com.cn/shop/S419378 | 2 条原站报价 |
| 云卡铺AI | https://www.16688.com.cn/shop/S360055 | 1 条原站报价 |
| CC的AI小店 | https://www.16688.com.cn/shop/S328141 | 1 条原站报价 |
| OEKK | https://www.16688.com.cn/shop/S411233 | 2 条原站报价 |
| 食过夜粥 | https://www.16688.com.cn/shop/S313118 | 3 条原站报价 |
| Apexqt | https://www.16688.com.cn/shop/S356114 | 2 条原站报价 |
| 犀利ai | https://www.16688.com.cn/shop/S177192 | 4 条原站报价 |
| 1633757959 | https://www.16688.com.cn/shop/S377741 | 1 条原站报价 |
| 喵懂AI | https://www.16688.com.cn/shop/S590689 | 2 条原站报价 |
| 传统ai | https://www.16688.com.cn/shop/S654941 | 1 条原站报价 |
| 独角兽AI阵地 | https://www.16688.com.cn/shop/S449417 | 2 条原站报价 |
| AI小圈 | https://www.16688.com.cn/shop/S428803 | 1 条原站报价 |
| 开放ai | https://www.16688.com.cn/shop/S494609 | 3 条原站报价 |
| Apexqt | https://www.16688.com.cn/shop/S451589 | 4 条原站报价 |
| 297jun的ai小铺 | https://www.16688.com.cn/shop/S494767 | 3 条原站报价 |
| sol批发谷歌 | https://gmailsol.com | 9 条原站报价 |
| 花生店铺 | https://store.codesky.qzz.io | 13 条原站报价 |
| AI充电站 | https://www.16688.com.cn/shop/S522050 | 1 条原站报价 |
| xiaofan | https://www.16688.com.cn/shop/S103121 | 2 条原站报价 |
| 1206157587 | https://www.16688.com.cn/shop/S757907 | 1 条原站报价 |
| 561237 | https://www.16688.com.cn/shop/S880200 | 1 条原站报价 |
| LF-Plus小铺 | https://www.16688.com.cn/shop/S419051 | 2 条原站报价 |
| 2061988325 | https://www.16688.com.cn/shop/S593431 | 3 条原站报价 |
| 好又来 | https://www.16688.com.cn/shop/S981692 | 4 条原站报价 |
| weiloo | https://shop.sunnydolls.dpdns.org | 7 条原站报价 |
| 大力小丸子 | https://www.16688.com.cn/shop/S154129 | 2 条原站报价 |
| 鸡皮提 | https://www.16688.com.cn/shop/S459971 | 4 条原站报价 |
| LLMOps | https://www.16688.com.cn/shop/S104738 | 4 条原站报价 |
| 惟源ai批发 | https://www.16688.com.cn/shop/S877035 | 6 条原站报价 |
| 麦当劳AI源头直供 对接马 MDLCARD | https://www.16688.com.cn/shop/S294441 | 2 条原站报价 |
| AI 加油站 | https://www.16688.com.cn/shop/S658333 | 2 条原站报价 |
| ai小兔 | https://www.16688.com.cn/shop/S123418 | 6 条原站报价 |
| saul！ | https://www.16688.com.cn/shop/S500854 | 1 条原站报价 |
| qqi425191 | https://www.16688.com.cn/shop/S984573 | 1 条原站报价 |
| 楠小铺 | https://www.16688.com.cn/shop/S594703 | 2 条原站报价 |
| 23754956 | https://www.16688.com.cn/shop/S617277 | 1 条原站报价 |
| 956140531 | https://www.16688.com.cn/shop/S555335 | 1 条原站报价 |
| 奥特曼的山姆店 | https://www.16688.com.cn/shop/S405392 | 1 条原站报价 |
| 龟龟的ai小铺 | https://www.16688.com.cn/shop/S229837 | 4 条原站报价 |
| 鸡排小铺 | https://www.16688.com.cn/shop/S844301 | 6 条原站报价 |
| 乐乐的AI小铺 | https://www.16688.com.cn/shop/S822189 | 5 条原站报价 |
| 烈阳AI | https://www.16688.com.cn/shop/S215070 | 2 条原站报价 |
| 魔仙堡AI | https://www.16688.com.cn/shop/S494090 | 1 条原站报价 |
| 牧之codex | https://www.16688.com.cn/shop/S683314 | 1 条原站报价 |
| 青蛙的AI小铺 | https://www.16688.com.cn/shop/S688003 | 5 条原站报价 |
| 全球代理发 | https://www.16688.com.cn/shop/S993490 | 2 条原站报价 |
| 图灵小店 | https://www.16688.com.cn/shop/S957578 | 2 条原站报价 |
| 团子Ai | https://www.16688.com.cn/shop/S284857 | 1 条原站报价 |
| 希音数卡 | https://www.16688.com.cn/shop/S718514 | 1 条原站报价 |
| 小鱼的Ai小店 | https://www.16688.com.cn/shop/S587759 | 1 条原站报价 |
| 新教长 | https://www.16688.com.cn/shop/S806917 | 1 条原站报价 |
| 玉米的AI小铺 | https://www.16688.com.cn/shop/S839885 | 6 条原站报价 |
| 鱼泡AI | https://www.16688.com.cn/shop/S559420 | 2 条原站报价 |
| 悦动ai | https://www.16688.com.cn/shop/S855300 | 1 条原站报价 |
| 中国小作坊 | https://www.16688.com.cn/shop/S594312 | 1 条原站报价 |
| AI 批发 | https://gpt.ybkjs.top | 已按原站页面/接口完成映射 |
| Bzcq的小店 | https://www.16688.com.cn/shop/S926745 | 1 条原站报价 |
| Hoshino | https://www.16688.com.cn/shop/S417540 | 1 条原站报价 |
| GOPLUS | https://www.16688.com.cn/shop/S625784 | 3 条原站报价 |
| ixxxn | https://www.16688.com.cn/shop/S293116 | 2 条原站报价 |
| jack神秘商店 | https://www.16688.com.cn/shop/S519281 | 1 条原站报价 |
| Jin AI | https://www.16688.com.cn/shop/S790246 | 3 条原站报价 |
| Mi的小铺 | https://www.16688.com.cn/shop/S624450 | 1 条原站报价 |
| moyanovo | https://www.16688.com.cn/shop/S835509 | 11 条原站报价 |
| NBPLUS | https://www.16688.com.cn/shop/S600383 | 2 条原站报价 |
| Tibo店铺-重置 | https://www.16688.com.cn/shop/S153234 | 1 条原站报价 |
| xxxxxn | https://www.16688.com.cn/shop/S891002 | 2 条原站报价 |
| Zero AI gmail超级老号批发 | https://www.16688.com.cn/shop/S841306 | 1 条原站报价 |
| ShopGPT | https://shopgpt.plus | 4 条原站报价 |
| 艾琳 | https://shop.aictk.shop | 12 条原站报价 |
| 大白发卡 | https://19cm.tech | 旧站首页迁移公告明确链接至新域名；跳转到第三方站点的推广卡片不作为本店商品采集 |
| Desolate 店铺 | https://fk.desolate.codes | 旧站 HTTP 302 直接指向新域名 |

## 原站确认的别名

| 名称 | 原站地址 | 结果 |
| --- | --- | --- |
| 梦泽Ai | https://www.16688.com.cn/shop/MENGZE | 原站证实与已接入地址指向同一店铺 |
| cc-cat | https://ccdawang.win/products | 原站证实与已接入地址指向同一店铺 |

## 尚未接通

| 名称 | 原站地址 | 结果 |
| --- | --- | --- |
| CC卡网 | https://cccrad.uk | robots.txt 禁止该路径采集 |
| GPT 自助下单充值系统 tehuio.com | https://tehuio.com | robots.txt 禁止该路径采集 |
| 王哈哈Ai | http://shop.whh985.com | 来源必须使用公开域名的 HTTPS 地址 |
| 鲸鲨源头 | https://chong.nerver.cc | 原站 HTTP 200，需核验独立页面结构 |
| JieAiTop | https://wzyp.cn/shop/N90HTB7K | 源站 HTTP 520 |
| 王哈哈Ai-Plus Pro源头直供【招代理】 | https://wzyp.cn/shop/whh985 | 源站 HTTP 520 |
| 彩虹AI | https://wzyp.cn/shop/ONX6ZOWB | 无法确认 robots.txt (520) |
| AI搬运工 | https://wzyp.cn/shop/2WMCCNSQ | 无法确认 robots.txt (520) |
| 小恐龙发卡网 | https://morimm.com | robots.txt 禁止该路径采集 |
| 小久 | https://wzyp.cn/shop/xiaojiuban | 无法确认 robots.txt (520) |
| AI源头批发旗舰店 | https://wzyp.cn/shop/SubAIP | 无法确认 robots.txt (520) |
| 星连ai旗舰店 | https://wzyp.cn/shop/aiplus666 | 无法确认 robots.txt (520) |
| 小久 | https://98-xj.com | The operation was aborted due to timeout |
| AI 云智聪聪 | https://wzyp.cn/shop/Z6I0VZ0Q | 无法确认 robots.txt (520) |
| CC卡网 | https://wzyp.cn/shop/cccard | 无法确认 robots.txt (520) |
| 陆柒科技 | https://wzyp.cn/shop/M18V0XVF | 无法确认 robots.txt (520) |
| 沐风源头 | https://shop.mfttai.com | The operation was aborted due to timeout |
| Oiai | https://wzyp.cn/shop/oiai | 无法确认 robots.txt (520) |
| My的Ai小铺 | https://wzyp.cn/shop/ZZ88VR4W | 无法确认 robots.txt (520) |
| AI小铺 | https://wzyp.cn/shop/echo_dream | 无法确认 robots.txt (520) |
| 稳中求胜 | https://wzyp.cn/shop/P98T49H8 | 无法确认 robots.txt (520) |
| AI_云顶👑【源头认证】 | https://wzyp.cn/shop/9M16S7R3 | 无法确认 robots.txt (520) |
| ai能量小铺 | https://wzyp.cn/shop/S5UL3UHI | 无法确认 robots.txt (520) |
| 鹰鹰小铺 | https://wzyp.cn/shop/GUEOI7Z9 | 无法确认 robots.txt (520) |
| Ai俱乐部 | https://wzyp.cn/shop/Aying | 无法确认 robots.txt (520) |
| G 优惠成品代充 | https://wzyp.cn/shop/JLDAK3FZ | 无法确认 robots.txt (520) |
| Ai小铺-源头供货-招代理-分销码：k6u37bm4 | https://wzyp.cn/shop/IY16OXB7 | 无法确认 robots.txt (520) |
| AI小家 | https://wzyp.cn/shop/5KF19IU0 | 无法确认 robots.txt (520) |
| 商家8719 | https://wzyp.cn/shop/SJ1BEJAC | 无法确认 robots.txt (520) |
| 亚米整合服务供应商 | https://wzyp.cn/shop/ymymai | 无法确认 robots.txt (520) |
| 海海星星AI | https://wzyp.cn/shop/J8CANM9Q | 无法确认 robots.txt (520) |
| Ai稳定供应（Grok/G.pt/Gemini源头直供）招代理对接码grok888 | https://wzyp.cn/shop/ai16888 | 无法确认 robots.txt (520) |
| Ai小伙计 | https://wzyp.cn/shop/153180461 | 无法确认 robots.txt (520) |
| 狗儿 | https://wzyp.cn/shop/2TF3CYFL | 无法确认 robots.txt (520) |
| NiuGe AI 加钟站 | https://wzyp.cn/shop/GU3XQH61 | 无法确认 robots.txt (520) |
| 迷途小铺 | https://wzyp.cn/shop/gpt88 | 无法确认 robots.txt (520) |
| Tora-雪诺AI代购娘小铺 | https://wzyp.cn/shop/Tora | 无法确认 robots.txt (520) |
| 我有米奇妙妙屋 | https://wzyp.cn/shop/8U6H8VI3 | 无法确认 robots.txt (520) |
| 橘子Ai源头🍊成品号批发 | https://wzyp.cn/shop/KFLA | 无法确认 robots.txt (520) |
| 琪琪科技 | https://wzyp.cn/shop/ZPISRC7G | 无法确认 robots.txt (520) |
| 卡比拉 | https://wzyp.cn/shop/kabila | 无法确认 robots.txt (520) |
| 小JIANG的商店 | https://wzyp.cn/shop/XSMWW894 | 无法确认 robots.txt (520) |
| SHEN | https://wzyp.cn/shop/DF6CKF46 | 无法确认 robots.txt (520) |
| ZZ源头批发 | https://wzyp.cn/shop/XiaoYie | 无法确认 robots.txt (520) |
| Tim的AI便利店 | https://wzyp.cn/shop/Tim_AI | 无法确认 robots.txt (520) |
| GAI源头 | https://wzyp.cn/shop/aimfshop | 无法确认 robots.txt (520) |
| 炒鸡变黑的AI店（对接码chaoji，Plus龟头卷价版） | https://wzyp.cn/shop/chaoji | 无法确认 robots.txt (520) |
| 极客ai Hub | https://wzyp.cn/shop/93FVU5NK | 无法确认 robots.txt (520) |
| AI万能工具箱 | https://wzyp.cn/shop/grok | 无法确认 robots.txt (520) |
| moyanovo | https://wzyp.cn/shop/moyanovo | 无法确认 robots.txt (520) |
| 冷热lab | https://wzyp.cn/shop/5OFQXIM1 | 无法确认 robots.txt (520) |
| 海神-Ai-大玩家（招代理） | https://wzyp.cn/shop/KFNRCFGC | 无法确认 robots.txt (520) |
| 52AI店铺 | https://wzyp.cn/shop/52AI | 无法确认 robots.txt (520) |
| HZ-API | https://wzyp.cn/shop/hzapi | 无法确认 robots.txt (520) |
| 602 | https://wzyp.cn/shop/602 | 无法确认 robots.txt (520) |
| YUJI | https://wzyp.cn/shop/YUJI | 无法确认 robots.txt (520) |
| iKun AI源头小铺 | https://wzyp.cn/shop/ikun666 | 无法确认 robots.txt (520) |
| 牟利ai | https://wzyp.cn/shop/2VWX76A4 | 无法确认 robots.txt (520) |
| 个性个性AI源头批发 | https://wzyp.cn/shop/WURK0XWX | 无法确认 robots.txt (520) |
| 464 | https://wzyp.cn/shop/7HVUEC3Y | 无法确认 robots.txt (520) |
| 金幺の小店 | https://wzyp.cn/shop/911 | 无法确认 robots.txt (520) |
| 卷子ai ( Lucky ) | https://wzyp.cn/shop/X23TO6QE | 无法确认 robots.txt (520) |
| 黑白小狗AI旗舰店 | https://wzyp.cn/shop/5R8T9H0Q | 无法确认 robots.txt (520) |
| AI小猫【招代理】 | https://wzyp.cn/shop/aixiaomao | 无法确认 robots.txt (520) |
| 青蛙AI·低价源头 | https://wzyp.cn/shop/qingwaAA | 无法确认 robots.txt (520) |
| 小高老板娘的AI | https://wzyp.cn/shop/O1PF7YKC | 无法确认 robots.txt (520) |
| 幻境MirageAI | https://wzyp.cn/shop/mirage | 无法确认 robots.txt (520) |
| flyai.qzz.io | https://flyai.qzz.io | The operation was aborted due to timeout |
| G小铺 | https://wzyp.cn/shop/gptxp | 无法确认 robots.txt (520) |
| 大魔王的店铺 | https://wzyp.cn/shop/EREZLCWN | 无法确认 robots.txt (520) |
| 教父 | https://wzyp.cn/shop/yanfu | 无法确认 robots.txt (520) |
| 【AI源头直供】AICA | https://wzyp.cn/shop/aica | 无法确认 robots.txt (520) |
| 抢抢的AI小铺 | https://wzyp.cn/shop/GQ6OBICY | 无法确认 robots.txt (520) |
| 云边小铺（招代理） | https://wzyp.cn/shop/one | 无法确认 robots.txt (520) |
| OpcAi_Family | https://wzyp.cn/shop/TVHUVT0A | 无法确认 robots.txt (520) |
| GCard | https://wzyp.cn/shop/YY4KVE2T | 无法确认 robots.txt (520) |
| 哈哈的ai杂货铺 | https://wzyp.cn/shop/22DHYNNV | 无法确认 robots.txt (520) |
| yes_code | https://wzyp.cn/shop/yes_code | 无法确认 robots.txt (520) |
| aihome | https://wzyp.cn/shop/gpt_plus | 无法确认 robots.txt (520) |
| FranklyBuilds的AI小店 | https://wzyp.cn/shop/7LFUCYI0 | 无法确认 robots.txt (520) |
| OF会员服务商 | https://wzyp.cn/shop/OFAI | 无法确认 robots.txt (520) |
| ydd | https://wzyp.cn/shop/TH52WUW7 | 无法确认 robots.txt (520) |
| AI小屋 | https://wzyp.cn/shop/rgzn | 无法确认 robots.txt (520) |
| 追梦AI | https://wzyp.cn/shop/FRNX1ZU8 | 无法确认 robots.txt (520) |
| 小熊AI | https://wzyp.cn/shop/YTR60TGVK | 无法确认 robots.txt (520) |
| chiyu | https://wzyp.cn/shop/OUJ1HPBV | 无法确认 robots.txt (520) |
| AI-小站 | https://wzyp.cn/shop/8998TM6I | 无法确认 robots.txt (520) |
| ai小助手 | https://wzyp.cn/shop/1PY3OQ46 | 无法确认 robots.txt (520) |
| 沈万三的AI聚宝盆 | https://wzyp.cn/shop/shenwansan | 无法确认 robots.txt (520) |
| 超级码少 | https://wzyp.cn/shop/cjms | 无法确认 robots.txt (520) |
| 猫咔 - Gemini源头批发 | https://catcard.uk | 原站商品 API 返回 Cloudflare 验证页，未绕过访问限制 |
| 奥特曼严选 | https://wzyp.cn/shop/PAXOVOVJ | 无法确认 robots.txt (520) |
| 词生量 | https://wzyp.cn/shop/2POVTUTK | 无法确认 robots.txt (520) |
| La ai | https://wzyp.cn/shop/aisell | 无法确认 robots.txt (520) |
| 沐沐的店 | https://wzyp.cn/shop/8Q9RHH0W | 无法确认 robots.txt (520) |
| ai成品 | https://wzyp.cn/shop/6YEJH8PE | 无法确认 robots.txt (520) |
| 小猴源头（越南实卡源头）对接码：33 | https://wzyp.cn/shop/xiaohou | 无法确认 robots.txt (520) |
| 哈基米站 | https://wzyp.cn/shop/DGF2IE5W | 无法确认 robots.txt (520) |
| G plus专卖 | https://wzyp.cn/shop/gptpluspro | 无法确认 robots.txt (520) |
| 稳问AI --AI 大玩家（AI真源头，招代理） | https://wzyp.cn/shop/aishop1 | 无法确认 robots.txt (520) |
| AI低价源头店 | https://wzyp.cn/shop/RRIM3VSF | 无法确认 robots.txt (520) |
| Hug AI | https://wzyp.cn/shop/4UOATQTU | 无法确认 robots.txt (520) |
| 797 | https://wzyp.cn/shop/42KWTJGE | 无法确认 robots.txt (520) |
| ton | https://wzyp.cn/shop/ton | 无法确认 robots.txt (520) |
| 光之国AI | https://wzyp.cn/shop/GT7KX1TN | 无法确认 robots.txt (520) |
| AI华强北 | https://wzyp.cn/shop/1001 | 无法确认 robots.txt (520) |
| ALL IN AI | https://wzyp.cn/shop/6H72NFWO | 无法确认 robots.txt (520) |
| aicloudhub | https://wzyp.cn/shop/aicloudhub | 无法确认 robots.txt (520) |
| 张啊三 | https://wzyp.cn/shop/623I7MCW | 无法确认 robots.txt (520) |
| AI杂货 | https://wzyp.cn/shop/2E2KPQD1 | 无法确认 robots.txt (520) |
| 猫王AI高品质源头 · 官方自营小铺 | https://wzyp.cn/shop/CZSYP67X | 无法确认 robots.txt (520) |
| 蜗的AI(招代理) | https://wzyp.cn/shop/woniu | 无法确认 robots.txt (520) |
| tototo | https://wzyp.cn/shop/FZKZDJ3U | 无法确认 robots.txt (520) |
| 麦门商店 | https://ouvg.top | 原站 HTTP 200，需核验独立页面结构 |
| 咔咔 | https://wzyp.cn/shop/D92VW084 | 无法确认 robots.txt (520) |
| Ai小铺 | https://wzyp.cn/shop/WPXSCE1B | 无法确认 robots.txt (520) |
| 猫猫豆 | https://wzyp.cn/shop/mmdou | 无法确认 robots.txt (520) |
| 郁川 G源头【招代理】对接码：yuchuan666 | https://wzyp.cn/shop/Yu_1an666 | 无法确认 robots.txt (520) |
| 伊莉雅·曜辰 | https://wzyp.cn/shop/ZM24RG4J | 无法确认 robots.txt (520) |
| 土豆 | https://wzyp.cn/shop/tudou | 无法确认 robots.txt (520) |
| 蛋的AI🔥 | https://wzyp.cn/shop/M5WLYYQV | 无法确认 robots.txt (520) |
| 初草的AI学习商品小铺 | https://wzyp.cn/shop/V2M14U73 | 无法确认 robots.txt (520) |
| 喵喵AI小铺2061 | https://wzyp.cn/shop/AG7CVCOD | 无法确认 robots.txt (520) |
| 精选好货AI | https://wzyp.cn/shop/jingxuan | 无法确认 robots.txt (520) |
| LynnZee | https://wzyp.cn/shop/GAXW96YR | 无法确认 robots.txt (520) |
| AI小店 | https://wzyp.cn/shop/YA3NLPX6 | 无法确认 robots.txt (520) |
| 幽羊 AI | https://wzyp.cn/shop/Z65QS0QG | 无法确认 robots.txt (520) |
| AI批发 | https://wzyp.cn/shop/ai-plus | 无法确认 robots.txt (520) |
| 还没想好 | https://wzyp.cn/shop/KIJSS7TJ | 无法确认 robots.txt (520) |
| 卡卡丨货源 | https://wzyp.cn/shop/kaka | 无法确认 robots.txt (520) |
| 懒羊羊AI | https://wzyp.cn/shop/lanyy | 无法确认 robots.txt (520) |
| 撸秃奥特曼 | https://wzyp.cn/shop/RT2XW6IY | 无法确认 robots.txt (520) |
| 晴天小店 | https://cool.cheggnow.com | The operation was aborted due to timeout |
| 云智仓AI | https://wzyp.cn/shop/2XZ9M71J | 无法确认 robots.txt (520) |
| 悦AI | https://wzyp.cn/shop/3BFKDGS3 | 无法确认 robots.txt (520) |
| 葫芦娃 | https://wzyp.cn/shop/B9KFCWFO | 无法确认 robots.txt (520) |
| 奥特曼大表哥 | https://wzyp.cn/shop/I7G8TG30 | 无法确认 robots.txt (520) |
| AI小店 | https://wzyp.cn/shop/cwyhlt | 无法确认 robots.txt (520) |
| ai小店 | https://wzyp.cn/shop/YAPYIJ9E | 无法确认 robots.txt (520) |
| Asuka的小店 | https://wzyp.cn/shop/36XN8ELM | 无法确认 robots.txt (520) |
| 咕咕嘎嘎 | https://wzyp.cn/shop/oaoi | 无法确认 robots.txt (520) |
| 小票的ai小铺 | https://wzyp.cn/shop/xiaopiao | 无法确认 robots.txt (520) |
| YCYAPI | https://wzyp.cn/shop/ycyapi | 无法确认 robots.txt (520) |
| 蚂蚁AI | https://wzyp.cn/shop/antmall | 无法确认 robots.txt (520) |
| 元筑AI 分销码 h8wthq46 | https://wzyp.cn/shop/laoyang | 无法确认 robots.txt (520) |
| 晓风ai | https://wzyp.cn/shop/xiaofeng | 无法确认 robots.txt (520) |
| Jin AI | https://wzyp.cn/shop/QGBCRJL0 | 无法确认 robots.txt (520) |
| 7QAI批发市场 | https://wzyp.cn/shop/1490777 | 无法确认 robots.txt (520) |
| 陈平安 | https://wzyp.cn/shop/NFCG5CVM | 无法确认 robots.txt (520) |
| 太一的店铺 | https://wzyp.cn/shop/IHWX6MX8 | 无法确认 robots.txt (520) |
| 飞龙 AI 小铺 | https://wzyp.cn/shop/rimon | 无法确认 robots.txt (520) |
| E ai | https://wzyp.cn/shop/2NAVZ50J | 无法确认 robots.txt (520) |
| 狗头AI（招代理） | https://wzyp.cn/shop/L9O8CDHA | 无法确认 robots.txt (520) |
| ChatGPlus 陌路专营店 分销码molu | https://wzyp.cn/shop/TD6GILQR | 无法确认 robots.txt (520) |
| AI练习生 | https://wzyp.cn/shop/5H4X93E5 | 无法确认 robots.txt (520) |
| AI魔法铺 | https://wzyp.cn/shop/magic_paw | 无法确认 robots.txt (520) |
| 芙芙的宝箱 | https://wzyp.cn/shop/fufu | 无法确认 robots.txt (520) |
| 风起Ai小卖铺 | https://wzyp.cn/shop/FengAi | 无法确认 robots.txt (520) |
| ai1998 | https://wzyp.cn/shop/ai1998 | 无法确认 robots.txt (520) |
| gemini源头直供 | https://wzyp.cn/shop/W50I8DVY | 无法确认 robots.txt (520) |
| 映核资源站 | https://wzyp.cn/shop/DJFT26BF | 无法确认 robots.txt (520) |
| RoAi | https://wzyp.cn/shop/JNPC971G | 无法确认 robots.txt (520) |
| 旺旺铺子 | https://wzyp.cn/shop/6D0QLK0N | 无法确认 robots.txt (520) |
| 灵AI | https://wzyp.cn/shop/H2QPI3X2 | 无法确认 robots.txt (520) |
| Royce | https://wzyp.cn/shop/IK1XF5CA | 无法确认 robots.txt (520) |
| stayAI | https://wzyp.cn/shop/QHN4YVQP | 无法确认 robots.txt (520) |
| jev | https://wzyp.cn/shop/WR09NYJN | 无法确认 robots.txt (520) |
| 【换地址了】ChihayaAI 【https://shop.sakisaki.top/】 | https://wzyp.cn/shop/anon | 无法确认 robots.txt (520) |
| 翻车咩萝 | https://wzyp.cn/shop/TSYOVSIV | 无法确认 robots.txt (520) |
| Reverse | https://wzyp.cn/shop/8TD03O0W | 无法确认 robots.txt (520) |
| SMS-AIShop | https://wzyp.cn/shop/66666SMS | 无法确认 robots.txt (520) |
| ai小卖部 | https://wzyp.cn/shop/SGJ71TXK | 无法确认 robots.txt (520) |
| ai链动 | https://wzyp.cn/shop/1H2U5JTI | 无法确认 robots.txt (520) |
| Gemini AI折扣站 | https://wzyp.cn/shop/8888 | 无法确认 robots.txt (520) |
| 彩虹马的AI店 | https://wzyp.cn/shop/AWXK3UJY | 无法确认 robots.txt (520) |
| MMB补给站 | https://wzyp.cn/shop/KLAOH7AK | 无法确认 robots.txt (520) |
| AIFXO | https://wzyp.cn/shop/aifxo | 无法确认 robots.txt (520) |
| huihuiaoao | https://wzyp.cn/shop/N3BQ0GOI | 无法确认 robots.txt (520) |
| 商家3500 | https://wzyp.cn/shop/JXFBLWPZ | 无法确认 robots.txt (520) |
| G成品号 | https://wzyp.cn/shop/FDX91PV6 | 无法确认 robots.txt (520) |
| Auto Subscribe | https://shop.auto-subscribe.com | robots.txt 禁止该路径采集 |
| 怪兽AI | https://wzyp.cn/shop/NWH6ORAI | 无法确认 robots.txt (520) |
| 蓝创API | https://wzyp.cn/shop/X2MZJRAY | 无法确认 robots.txt (520) |
| Grape AI🍇 | https://wzyp.cn/shop/JYO0X15L | 无法确认 robots.txt (520) |
| KeikoAI小店 | https://wzyp.cn/shop/keiko | 无法确认 robots.txt (520) |
| AI小铺（源头直供，招代理） | https://wzyp.cn/shop/chatgpt_ai | 无法确认 robots.txt (520) |
| Doro AI | https://wzyp.cn/shop/doroai | 无法确认 robots.txt (520) |
| 海飞丝AI | https://wzyp.cn/shop/haifs | 无法确认 robots.txt (520) |
| ai小铺 | https://wzyp.cn/shop/8DUJDZSR | 无法确认 robots.txt (520) |
| Kstar | https://wzyp.cn/shop/UJLFBVR9 | 无法确认 robots.txt (520) |
| 启灵AI | https://wzyp.cn/shop/H81FWD0T | 无法确认 robots.txt (520) |
| 鱼ai | https://wzyp.cn/shop/S8EK3HL5 | 无法确认 robots.txt (520) |
| diyun小铺 | https://wzyp.cn/shop/IUWAYNYR | 无法确认 robots.txt (520) |
| kiro源头 | https://wzyp.cn/shop/1XZXKYZB | 无法确认 robots.txt (520) |
| 养乐多 | https://wzyp.cn/shop/FC6GCKGG | 无法确认 robots.txt (520) |
| 大卖 AI | https://wzyp.cn/shop/damai | 无法确认 robots.txt (520) |
| 星光ai | https://wzyp.cn/shop/8X8DYGEW | 无法确认 robots.txt (520) |
| Apex AI | https://wzyp.cn/shop/ApexAI | 无法确认 robots.txt (520) |
| 源头卡密 | https://wzyp.cn/shop/F06LXGPS | 无法确认 robots.txt (520) |
| TiboProMax | https://wzyp.cn/shop/OP96OFEN | 无法确认 robots.txt (520) |
| BrothersAI | https://wzyp.cn/shop/TJFXRQD5 | 无法确认 robots.txt (520) |
| Ai小店1150 | https://wzyp.cn/shop/QLL06630 | 无法确认 robots.txt (520) |
| mortyAI小铺 | https://wzyp.cn/shop/C7MLWX4N | 无法确认 robots.txt (520) |
| 乌鸦AI | https://wzyp.cn/shop/B8JKQFDK | 无法确认 robots.txt (520) |
| DeepToken | https://wzyp.cn/shop/DeepToken | 无法确认 robots.txt (520) |
| LMark | https://wzyp.cn/shop/ELSXOANJ | 无法确认 robots.txt (520) |
| 乐天图书馆 | https://wzyp.cn/shop/lotte-library | 无法确认 robots.txt (520) |
| PLUS直营店 | https://wzyp.cn/shop/FNAOIGBK | 无法确认 robots.txt (520) |
| ali.shop | https://wzyp.cn/shop/9P102ZA3 | 无法确认 robots.txt (520) |
| 青卿 | https://wzyp.cn/shop/qingqing | 无法确认 robots.txt (520) |
| 恶小梦 | https://wzyp.cn/shop/J6F0Z1MF | 无法确认 robots.txt (520) |
| 柠檬西瓜 | https://lemon-watermelon.com | 原站 HTTP 200，需核验独立页面结构 |
| 双子星AI | https://wzyp.cn/shop/hajimi3303 | 无法确认 robots.txt (520) |
| TxyxT小店 - GPT Plus、GPT Pro、Gemini Pro等AI充值服务 | https://shop.txyxt.dpdns.org | robots.txt 禁止该路径采集 |
| PopcornAPI | https://wzyp.cn/shop/A7QPIQGQ | 无法确认 robots.txt (520) |
| Moert AI（招代理） | https://wzyp.cn/shop/D8EH8M0Y | 无法确认 robots.txt (520) |
| 雨辉小店 | https://wzyp.cn/shop/JDMUNQEK | 无法确认 robots.txt (520) |
| 祖传手艺人 | https://wzyp.cn/shop/Qudong | 无法确认 robots.txt (520) |
| xinai | https://wzyp.cn/shop/Z3N2T2TB | 无法确认 robots.txt (520) |
| 小七AI 实验室 | https://wzyp.cn/shop/JZJOPMQD | 无法确认 robots.txt (520) |
| AI深研社 | https://wzyp.cn/shop/FAJMDFWV | 无法确认 robots.txt (520) |
| AI天使 | https://wzyp.cn/shop/X3LOY3DI | 无法确认 robots.txt (520) |
| YYYYD | https://wzyp.cn/shop/LD52LLPD | 无法确认 robots.txt (520) |
| AI开发商 | https://wzyp.cn/shop/ai.shop | 无法确认 robots.txt (520) |
| Auto Subscribe / ultra.makelove.cloud | https://ultra.makelove.cloud | robots.txt 禁止该路径采集 |
| 悦动ai | https://wzyp.cn/shop/DUMGWJ8A | 无法确认 robots.txt (520) |
| AI铺子 | https://wzyp.cn/shop/claudeai | 无法确认 robots.txt (520) |
| AI大卖家 | https://wzyp.cn/shop/W89ITLDC | 无法确认 robots.txt (520) |
| 7878 | https://wzyp.cn/shop/6TKPIT5E | 无法确认 robots.txt (520) |
| 北极星 | https://wzyp.cn/shop/beijixing | 无法确认 robots.txt (520) |
| 大力小丸子 | https://wzyp.cn/shop/CWMYU83X | 无法确认 robots.txt (520) |
| 便宜的codex的小铺 | https://wzyp.cn/shop/E0Y14IRF | 无法确认 robots.txt (520) |
| 超梦ai | https://wzyp.cn/shop/R45NG4A8 | 无法确认 robots.txt (520) |
| 豪猪 | https://wzyp.cn/shop/GNS3838K | 无法确认 robots.txt (520) |
| 教长 | https://wzyp.cn/shop/DFT712GK | 无法确认 robots.txt (520) |
| 靠谱 AI | https://wzyp.cn/shop/1I2Y9GEC | 无法确认 robots.txt (520) |
| 李页的小店 | https://wzyp.cn/shop/liye | 无法确认 robots.txt (520) |
| 码愿AI | https://wzyp.cn/shop/6YHGJOPN | 无法确认 robots.txt (520) |
| 卖点AI | https://wzyp.cn/shop/7TCL10MR | 无法确认 robots.txt (520) |
| 猫猫AI | https://wzyp.cn/shop/O5JHRJFZ | 无法确认 robots.txt (520) |
| 摸鱼工坊 | https://wzyp.cn/shop/zcboy | 无法确认 robots.txt (520) |
| 模型契约 | https://wzyp.cn/shop/atm | 无法确认 robots.txt (520) |
| 南乔ai | https://wzyp.cn/shop/X273D51R | 无法确认 robots.txt (520) |
| 四米名字 | https://wzyp.cn/shop/P5034CNR | 无法确认 robots.txt (520) |
| 桃子的ai大店 | https://wzyp.cn/shop/taozi168 | 无法确认 robots.txt (520) |
| 无限AI | https://wzyp.cn/shop/T4JGK0GX | 无法确认 robots.txt (520) |
| 祥祥AI | https://wzyp.cn/shop/8ALLUCG3 | 无法确认 robots.txt (520) |
| 小易AI | https://wzyp.cn/shop/V3N6D2JM | 无法确认 robots.txt (520) |
| 小L专卖 | https://wzyp.cn/shop/M4XS1E3Q | 无法确认 robots.txt (520) |
| 优质源头科技 | https://wzyp.cn/shop/N6MIRGLW | 无法确认 robots.txt (520) |
| 云枢AI | https://wzyp.cn/shop/nextpro | 无法确认 robots.txt (520) |
| 智域AI服务 | https://wzyp.cn/shop/591J6Q87 | 无法确认 robots.txt (520) |
| 知客AI | https://wzyp.cn/shop/ESDBYE2X | 无法确认 robots.txt (520) |
| 专注ai | https://wzyp.cn/shop/29YZ9FO2 | 无法确认 robots.txt (520) |
| AI聚合商铺 | https://wzyp.cn/shop/Y1ZQF0RS | 无法确认 robots.txt (520) |
| Ai集成商 | https://wzyp.cn/shop/6DV9N2BT | 无法确认 robots.txt (520) |
| 专业AI订阅服务 | https://kapay.shop | robots.txt 禁止该路径采集 |
| AI小店 | https://wzyp.cn/shop/HV676A0A | 无法确认 robots.txt (520) |
| AI小地摊 | https://wzyp.cn/shop/openAI_codex | 无法确认 robots.txt (520) |
| AI小铺 | https://wzyp.cn/shop/25G53A8F | 无法确认 robots.txt (520) |
| AI小铺 | https://wzyp.cn/shop/AGQPN4LL | 无法确认 robots.txt (520) |
| ai源头店铺 | https://wzyp.cn/shop/EIQ423GT | 无法确认 robots.txt (520) |
| AI杂货铺 | https://wzyp.cn/shop/5HJZN0Q1 | 无法确认 robots.txt (520) |
| BugTeam源头 | https://wzyp.cn/shop/RINGYCWY | 无法确认 robots.txt (520) |
| ai主理人 | https://wzyp.cn/shop/TSW7DIEI | 无法确认 robots.txt (520) |
| CodeCtrclc-对接码1101 | https://wzyp.cn/shop/1101 | 无法确认 robots.txt (520) |
| Cookie AI | https://wzyp.cn/shop/cookieai | 无法确认 robots.txt (520) |
| G-gemini会员稳定低价 | https://wzyp.cn/shop/NUX4KNC4 | 无法确认 robots.txt (520) |
| G商号 | https://wzyp.cn/shop/FW0Q6UDA | 无法确认 robots.txt (520) |
| G小站 | https://wzyp.cn/shop/gptpromax | 无法确认 robots.txt (520) |
| Gemini批发 | https://wzyp.cn/shop/AZX4SPJ0 | 无法确认 robots.txt (520) |
| Ice Ai X | https://wzyp.cn/shop/iceaix | 无法确认 robots.txt (520) |
| MortalAi | https://wzyp.cn/shop/ZYGCPJD7 | 无法确认 robots.txt (520) |
| NPC小铺 | https://wzyp.cn/shop/RN3DIJIY | 无法确认 robots.txt (520) |
| X的ai小店 | https://wzyp.cn/shop/KN6NZBLA | 无法确认 robots.txt (520) |
| ZhiYu Ai | https://wzyp.cn/shop/mengyu | 无法确认 robots.txt (520) |
| 91网\|一手货源 | https://gmail91.shop | 无法确认 robots.txt (301) |
| Acc-OTAOR | https://xtacc.top | The operation was aborted due to timeout |
| 萃选ai（可开发票）联系客服下单免手续费 | https://www.16688.com.cn/shop/S428748 | 原站无法确认店铺身份 |
| 德玛西亚ai | https://pay.ldxp.cn/shop/Q5AIW19X | 旧域名未返回可验证的跳转 |
| 老饕AI源头 | https://www.16688.com.cn/shop/S990848 | 原站无法确认店铺身份 |
| 购物 - NoDeexs | https://nodeexs.com | fetch failed |
| 老中医X | https://wzyp.cn/shop/A3H9BD10 | 无法确认 robots.txt (520) |
| 青熵 | https://pay.ldxp.cn/shop/P9HPIPWA | 旧域名未返回可验证的跳转 |
| 全网低价GPT Team账号 | https://pay.ldxp.cn/shop/ZKVLK6KL | 旧域名未返回可验证的跳转 |
| 轻点小铺 \| 对接码：AA8PL | https://wzyp.cn/shop/468E0S05 | 无法确认 robots.txt (520) |
| 若真AI | https://www.16688.com.cn/shop/S782319 | 原站无法确认店铺身份 |
| 源头GPT/GEMINI（招代理） | https://pay.ldxp.cn/shop/ai0001.com | 旧域名未返回可验证的跳转 |
| A1gmail | https://www.16688.com.cn/shop/S799620 | 原站无法确认店铺身份 |
| 棱镜店铺 | https://shop.558686.xyz | 无法确认 robots.txt (502) |
| Ai小卖部 | https://pay.ldxp.cn/shop/D13I8BK4 | 旧域名未返回可验证的跳转 |
| AI杂货铺 | https://pay.ldxp.cn/shop/009527 | 旧域名未返回可验证的跳转 |
| BMCCA小铺 | https://pay.ldxp.cn/shop/BMCCA | 旧域名未返回可验证的跳转 |
| beibei | https://bei-bei.shop | 源站 HTTP 403 |
| freejson | https://pay.ldxp.cn/shop/3KBNYI29 | 旧域名未返回可验证的跳转 |
| Auto Subscribe / shop.aitonse.com | https://shop.aitonse.com | 无法确认 robots.txt (521) |
| GPT pro20x | https://sulanjun.cc | 无法确认 robots.txt (403) |
| LynnZee 店铺 | http://lynnzee.myweb999.cfd | 来源必须使用公开域名的 HTTPS 地址 |
| geekaihub.com | https://geekaihub.com | 源站 HTTP 404 |
| shop.olimap.top | https://shop.olimap.top | robots.txt 禁止该路径采集 |
| team | https://faka.aiceo.dev | 无法确认 robots.txt (403) |
| 账号小卖铺 | https://11.id2323.top | The operation was aborted due to timeout |
| YOYO小卖部 | https://pay.ldxp.cn/shop/RYRCN59O | 旧域名未返回可验证的跳转 |
| xxxyan | https://xxxyan.cc | robots.txt 禁止该路径采集 |
| jzai1688.com | https://jzai1688.com | The operation was aborted due to timeout |
| n1.ccnmgpt.com | https://n1.ccnmgpt.com | The operation was aborted due to timeout |

完整机器可读记录见 [merchant-coverage.json](merchant-coverage.json)，待接入清单见 [pending-sources.json](../config/pending-sources.json)。这是一份带时间戳的核验结果；原站服务恢复或迁移后需要重新核验。
