# 用户提供的 PriceAI 来源线索核验

核验日期：2026-10-07。候选域名来自用户指定的 [collectors.json](https://github.com/dimthink/PriceAI/blob/main/config/collectors.json) 与 [BUILTIN_SOURCES](https://github.com/dimthink/PriceAI/blob/main/scripts/collect-prices.mjs)。这里记录实际访问原商家后的结果，不代表 PriceAI 线上全部商家。店名、配置和价格取自原商家；没有复制 PriceAI 的采集器实现或生产报价。

新增 21 家通过部署在 Cloudflare 的试采集和正式采集，共写入 371 条商品报价。连同原有 6 家，目前启用 27 家；公开 API 核验为 463 条报价。其中包含邮箱及其他商品，不能把全部数量称为 AI 订阅套餐数。

新增来源每 6 小时刷新，原有来源仍为每小时。当时每 5 分钟最多采集 2 家，理论每小时容量 24 家；该批来源正常刷新需求约 9.5 家/小时，失败重试另占容量。实际定时执行应持续以 Worker 日志为准。

后续多店扩充与调度容量调整见 [多店采集记录](multishop-onboarding.md)。

## 已接入

| 商家                                    | 原站                            | 采集器 | 首次线上报价数 |
| --------------------------------------- | ------------------------------- | ------ | -------------- |
| Aisou智充                               | https://aisou.pro/              | kami   | 25             |
| T佬的gmail批发渠道                      | https://ai666.dnxb.cc/          | kami   | 7              |
| Gemini账号批发douyiner.cn               | https://douyiner.cn/            | kami   | 13             |
| 七叔数字社                              | https://ai666.id/               | kami   | 59             |
| AI 会员代充，即买即用 - Florence AI     | https://faka.redeemai.me/       | kami   | 8              |
| 86GameStore                             | https://faka.redeemgpt.com/     | kami   | 16             |
| Goutou小铺                              | https://fk.gptcz.cc/            | kami   | 3              |
| 谷歌邮箱 AI源头批发                     | https://hiemail.store/          | kami   | 16             |
| NikoCard                                | https://nikoers.com/            | kami   | 8              |
| 笔墨小铺- 专供GPT Claude Gemini相关羊毛 | https://shop.bmoplus.com/       | kami   | 2              |
| shopcardai.click                        | https://shopcardai.click/       | kami   | 10             |
| 异次元店铺                              | https://shihuiai.cn/            | kami   | 10             |
| 蔚莱云Ai出海跨境账号                    | https://web3chirou.com/         | kami   | 97             |
| Wiki123 卡网                            | https://wiki123.top/            | kami   | 3              |
| yh-mo源头批发                           | https://yh-mo.xyz/              | kami   | 11             |
| ac-card.org                             | https://ac-card.org/            | dujiao | 5              |
| burstpro-ai.online                      | https://burstpro-ai.online/     | dujiao | 45             |
| ccdawang.win                            | https://ccdawang.win/           | dujiao | 10             |
| zhang520.store                          | https://zhang520.store/         | dujiao | 4              |
| AUTO FK                                 | https://aifk.opensora.de/       | html   | 2              |
| 小黑丸                                  | https://upgrade.xiaoheiwan.com/ | html   | 17             |

AUTO FK 与小黑丸只解析首页可见商品，设置 `full_snapshot: false`，不把首页遗漏商品视为下架。HTML 库存支持精确去掉 `库存：` 前缀，再判断数值；其他无法确认的库存保留为未知。

## 未接入及待适配

下列是本次访问结果，网络错误可能随时间变化。失败不会写入来源表，已有解析器不适用的站点不通过猜测字段强行接入。

| 候选原站                           | 核验结果                                                |
| ---------------------------------- | ------------------------------------------------------- |
| https://caowo.store/               | fetch failed                                            |
| https://fk.gptkt.pro/              | Unexpected token '<', "<!doctype "... is not valid JSON |
| https://shop.auto-subscribe.com/   | robots.txt 禁止该路径采集                               |
| https://pay.ldxp.cn/shop/jinyao    | fetch failed                                            |
| https://makerich.club/             | fetch failed                                            |
| https://pay.ldxp.cn/shop/pixelshop | fetch failed                                            |
| https://pay.qxvx.cn/               | fetch failed                                            |
| https://acg.nbcode.xyz/            | fetch failed                                            |
| https://123456787kelie.top/        | The operation was aborted due to timeout                |
| https://feifei.shop/               | The operation was aborted due to timeout                |
| https://fk.ybkjs.top/              | fetch failed                                            |
| https://gemini91.shop/             | fetch failed                                            |
| https://gmail1888.com/             | fetch failed                                            |
| https://lynnzee.myweb999.cfd/      | fetch failed                                            |
| https://shop.558686.xyz/           | 源站 HTTP 502                                           |
| https://shop.gpt365.wiki/          | 源站 HTTP 403                                           |
| https://talkai.cyou/               | 来源发生跳转，请确认并更新来源 URL                      |
| https://tehuio.com/                | robots.txt 禁止该路径采集                               |
| https://zzshu.com/                 | fetch failed                                            |
| https://98-xj.com/                 | 无效价格                                                |
| https://11.id2323.top/             | fetch failed                                            |
| https://card.kxandyou.com/         | 源站 HTTP 404                                           |
| https://fk.txspvip.xyz/            | fetch failed                                            |
| https://geekaihub.com/             | 源站 HTTP 404                                           |
| https://gmail91.shop/              | 来源发生跳转，请确认并更新来源 URL                      |
| https://kapay.shop/                | robots.txt 禁止该路径采集                               |
| https://shop.aitonse.com/          | 源站 HTTP 521                                           |
| https://morimm.com/                | robots.txt 禁止该路径采集                               |
| https://shop.mfttai.com/           | 来源发生跳转，请确认并更新来源 URL                      |
| https://ultra.makelove.cloud/      | robots.txt 禁止该路径采集                               |
| https://zhanghao66.com/            | 500: 无法确认 robots.txt (456)                          |
| https://ouvg.top/                  | 500: 无效价格                                           |

其他采集器类型的域名也检查了公开首页：小黑丸已适配；麦门商店现有页面存在无效价格，尚未接入。ikunlove.best、getgpt.pro、lemon-watermelon.com、xingbao-ai.shop、xxxyan.cc 尚需各自适配和购买链接核验；academicgate.org 当前可见的是订阅激活页，未确认公开商品目录。

bei-bei.shop、catcard.uk、sulanjun.cc 返回 403，sd.ncet.top 返回 521；meowka.vip、fk1.ybkjs.top、of365.vip 连接失败或超时。autopixel.qzz.io、woaimaihao.com 跳转到其他地址，尚未确认新来源；19cm.tech 是域名变更通知页。

ShopApi 清单中的 catfk.com、ldxp.cn 等域名可能是平台地址，不能直接作为一家具体小店。需要完整店铺路径或店铺标识；本次检查的 jinyao、pixelshop 路径和 pay.qxvx.cn 未通过原站访问。

robots 禁止或服务端拒绝的路径没有绕过限制。源码中的来源清单、接口类型和站点现状可能不同；Supabase 线上 sources 表也不在该公开仓库中，所以公开配置无法还原其全部线上店铺。
