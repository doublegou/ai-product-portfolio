# 购买链接核验（2026-10-10）

本轮对照公开报价、Supabase 来源配置与原站进行核验，基线为 4,778 条报价、365 个展示来源；合并同一商品的重复 SKU 后涉及 4,708 个购买地址。抓取只读公开内容，不下单、不登录商家、不提交支付或个人信息。

## 修复

- Kami 采集器错误地将商品购买地址默认拼为 `/commodity?id={id}`，但已核验的现行店铺使用 `/item/{id}`。默认值已修复，显式 `purchase_path` 仍优先，旧路由例外可继续配置。
- 本次迁移 021 更新 20 家店铺配置及 350 条活跃报价的购买链接。此前已修正的 7 家合计 70 条报价继续正确。已确认公开 JSON 中这 27 家、420 条报价均为 `/item/{id}`。
- 价格接口 `/user/api/index/commodity` 未改变，购买地址与价格读取相互独立。97 项测试、构建及数据库购买路径检查通过。
- 两条从完整商品目录消失的报价（G71452065、G31228644）经正常重新采集已停用；不通过手工改价来修复链接。

## 核验方式与边界

- 每个展示来源都尝试实际采集，商品编号、价格及生成的链接与来源数据对照。
- 16688 同平台商品使用原站完整目录中的 `goods_no` 对照 `/goods/{goods_no}`，并对每家店抽查实际 HTTP 商品路径；不等于逐个在浏览器打开其全部商品。
- 其他来源检查网页实际附加 UTM 后的地址。页面返回 200 并不足以判定正确；检查错误页、商品编号、标题，必要时解码页面静态 HTML 数据或用浏览器确认。通用外壳页面单独列为需复核。
- 修复后的 Kami 店铺再采集并复查：321 个购买页确认具体商品，1 个商品被本机浏览器拦截需复核；蔚莱云复查遇到访问防护，另用 Cloudflare 成功采到 98 条商品，并在浏览器确认 Codex 接码实际商品页。
- 本机采集 359/365 来源成功；两个 ybkjs 来源在本机 HTTPS 连接失败，但 Cloudflare 试采集成功，Supabase 也有新的成功记录。不能将本机失败直接视为全网停站。

## 仍需原站或后续复核的项目

| 来源 | 本次观察 |
|---|---|
| gpt.ybkjs.top、fk.ybkjs.top | 本机/浏览器连接失败，云端采集正常；购买地址与云端数据一致，但当前网络访问问题没有消失 |
| shop.aictk.shop | 502，生产采集记录亦有同类错误 |
| 16688 店铺 S935156、S840665 | 商品目录为空，采集保留历史报价，不能确认仍在售 |
| 16688 店铺 S277039 | 商品接口不可用，生产也有失败记录 |
| ai666.id/item/527 | 本机浏览器报 ERR_BLOCKED_BY_CLIENT，未标为浏览器验证通过 |

商品路径修复已部署到主 Worker、collect-prices、verify-hot-offers，并同步公开 JSON。第三方服务未来下架、换域名、防护或区域连接问题，仍需重新核验；本轮不承诺所有外站永久可访问。

## 本次配置更新的店铺

- https://kbshub.store
- https://google7676.top
- https://nikoers.com/
- https://wiki123.top/
- https://faka.redeemai.me/
- https://ai666.dnxb.cc/
- https://fk.10886.xyz
- https://dimosky.com/
- https://ai666.id/
- https://yh-mo.xyz/
- https://aisou.pro/
- https://shop.sunnydolls.dpdns.org
- https://faka.redeemgpt.com/
- https://faka.bbanai.site
- https://web3chirou.com/
- https://gmailsol.com
- https://hiemail.store/
- https://shop.bmoplus.com/
- https://shopcardai.click/
- https://aichongz.cc
