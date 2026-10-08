# 来源收录记录

当前只有明确验证过采集的商家才会启用。Cron 负责更新已配置来源，不自动发现商家。

2026-10-07 独立检索的新增来源：

| 来源       | 发现依据                                            | 采集方式                            | 首次线上结果                 |
| ---------- | --------------------------------------------------- | ----------------------------------- | ---------------------------- |
| 环球小铺   | 商家首页 https://gospv.com/ 的公开商品与 robots.txt | `/api/v1/public/products`，展开 SKU | 30 条                        |
| AI能量小店 | 商家首页 https://dimosky.com/ 的经营说明与商品分类  | Kami commodity 接口                 | 11 条                        |
| 炼丹师小铺 | 商家首页 https://lianduang.com/ 的商品分类          | Kami commodity 接口                 | 15 条                        |
| V3小店     | https://shop.gpt.ge/ 的公开商品链接                 | 服务端渲染 HTML，精确选择器         | 5 条，首页推荐商品的部分快照 |

上述首次批次通过公开搜索与商家页面独立查找，没有从 PriceAI 数据库、渠道列表或报价接口导入。后续按用户提供的 PriceAI 域名线索新增 21 家，核验详情见 [本次候选记录](referenced-sources-audit.md)。可复用的来源配置保存在 `config/verified-sources.json`，初始化种子在 `supabase/seed.sql`。这些文件只含来源配置，不含价格快照。

未启用的候选：CaiTou 与 uid.baby 当前直连失败；杂鱼小铺未完成可用性验证；AI补给站的实际商城指向另一域名，尚需独立验证商城接口；Ai66 的部分购买链接依赖前端脚本，尚未建立完整报价解析。它们不会被作为已经成功采集的商家展示。

## 扩充到更多商家

1. 从公开搜索、用户提供的网址、商家自荐找到候选，独立站按域名去重；多店平台按完整店铺路径／店号去重，同一域名可以对应多家来源。
2. 在 `/admin` 添加配置，使用“试采集”核对实际价格字段、SKU、购买链接与库存。
3. 确认商品范围是否完整；分页不足或首页仅推荐商品时不启用完整快照。
4. 保存后单独执行采集，检查日志，确认成功才算完成接入。
5. 持续检查失败、商品结构变化与报价过期。需要浏览器执行 JavaScript 的商家应另接浏览器采集节点，不能假设 Worker 能渲染动态页面。

当前每 5 分钟最多采集 8 家，理论每小时 96 家。新增多店来源每 12 小时更新，与原有每小时／每 6 小时来源共享队列；失败重试、超时和平台限额会影响实际容量。容量按完整 Cron 日志验证，继续扩店或缩短间隔时应增加队列／采集节点。多店扩充见 [核验记录](multishop-onboarding.md)。

## 对照 PriceAI 的公开说明

其 README 自述覆盖 200+ 渠道；数据流程包含公开来源、用户提交、导入和人工审核。采集文档列出原站 API、HTML 解析和本机浏览器兜底。它不是靠 Cron 自动发现全网店铺。

- https://github.com/dimthink/PriceAI
- https://github.com/dimthink/PriceAI/blob/main/public-docs/architecture.md
- https://github.com/dimthink/PriceAI/blob/main/public-docs/collectors.md
- https://github.com/dimthink/PriceAI/blob/main/DATA_LICENSE.md
