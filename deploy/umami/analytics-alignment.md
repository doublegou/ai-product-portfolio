# PriceMapAI 的 Umami 统计口径

参考 2026-10-09 的 [PriceAI 源码](https://github.com/dimthink/PriceAI/tree/b3092c4487ab96e58dd9d1fb97016ac692ea116e/src) 与 [线上站点](https://priceai.cc/)。线上使用 `umami.dimthink.com/script.js`；本项目使用自己的 `stats.pricemapai.com/script.js`、网站 ID `89ee5fce-9013-4146-a0bd-32e85e49cf15`，仅采集 `pricemapai.com`。

## 自动统计

Umami 自动提供访客、浏览量、访问会话、访问时长、跳出率、页面路径、来源、设备、浏览器、系统及国家/地区等统计，支持 SPA 页面切换。本项目排除 URL 查询参数和 hash；平台、套餐类型等交互由下列事件单独记录。

## 对齐已有功能

| PriceAI 事件 | PriceMapAI 操作 | 属性 |
| --- | --- | --- |
| `product_detail_open` | 全部分类商品详情、详情页套餐切换 | `product_id`、`platform`，目录入口另含 `product_type` |
| `platform_product_detail_open` | 指定平台分类中的商品详情 | `product_id`、`platform`、`product_type` |
| `purchase_link_click` | 原站购买 | `source_id`、`available` |
| `merchant_shop_click` | 商家首页 | `source_id` |
| `platform_filter_change` | 订阅分类、API 模型分类切换 | `platform`，API 另含 `surface` |
| `scope_change` | 从商品目录进入报价、返回目录 | `scope=offers/products`、`platform` |
| `advanced_filters_reset` | 无结果时重置筛选 | 无 |

列表/网格是显示方式，记录 `view_change`（`view`、`surface`），不混入 PriceAI 的商品/报价/商家范围 `scope_change`。API 现有功能补充 `api_type_change`、`api_station_detail_open` 和 `api_provider_click`，分别记录类型、中转站 ID、原站/报价入口；不记录搜索原文或任何 API Key。

本项目公开快照不包含商家数据库 UUID，因此订阅 `source_id` 使用商家域名和店铺路径作为稳定标识，不包含 query、aff 或 hash。API 使用已公开的中转站 ID。不能直接与 PriceAI 数据库里的商家 UUID 合并。

购买及商家链接保留商品路径、其他参数和已约定的 `aff`，加入 `utm_source=pricemapai.com`；campaign 使用 `pricemapai_card_shop`、`pricemapai_merchant`、`pricemapai_api_transit`、`pricemapai_official_api`。已有其他归因保留，PriceAI 归因替换；带签名或认证参数的链接不修改。

## 原项目有、本站暂无对应功能

| 事件 | 原项目功能 |
| --- | --- |
| `platform_landing_cta_click`、`platform_related_link_click` | 平台专题落地页 CTA、相关推荐 |
| `submit_channel_open`、`submit_source_success` | 公共渠道投稿 |
| `guide_prompt_dismiss` | 指南提示条 |
| `site_notice_impression`、`site_notice_dismiss`、`site_notice_click_primary` | 公告弹窗 |
| `sponsor_impression`、`sponsor_dismiss`、`sponsor_click` | 赞助位 |
| `support_nudge_impression`、`support_nudge_dismiss`、`support_nudge_click` | 支持作者提示 |

没有对应操作时不生成这些事件，不额外添加弹窗、赞助位或投稿功能。

## 查看统计

登录 <https://stats.pricemapai.com>，选择 PriceMapAI，在事件和事件数据中按上述事件名与属性查看商品热度、商家购买点击、库存状态和筛选偏好。漏斗可使用详情打开 → 购买点击；购买点击代表跳转意图，不代表商家成交。

PriceAI 的管理后台还调用 Umami API，读取最近一天的购买点击 `source_id` 来辅助商家采集优先级；它的赞助点击另有第一方 `/api/outbound-events` 数据库记录，并非只靠 Umami。本站由腾讯云每 15 分钟从本地数据库汇总不同会话的商家兴趣，并经 Cloudflare 转交 Supabase 自动调整商家采集间隔。它不使用 Umami 管理员密码，也不增加每位访客访问 Supabase 的请求；具体策略见 [增量与热度调度](../incremental/README.md)。

## 验证记录

2026-10-09 正式站浏览器验证完成，Umami 事件总览收到 15 次事件、11 个不同事件名，覆盖上表 7 个对齐事件和 4 个本站事件。返利链接已在正式页面验证保留 `aff` 与商品路径。归因和故障隔离的 7 项相关测试、TypeScript 检查和生产构建通过。Cloudflare 部署版本：`2ee9399b-1982-4365-a662-fa0d81cdff63`。
