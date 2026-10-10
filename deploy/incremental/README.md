# 增量快照与按热度采集

Supabase 是唯一报价数据库。现有两个每分钟 Cron 领取到期来源；每个来源的 `interval_minutes` 和 `next_crawl_at` 决定采集间隔，不为各个档位创建新 Cron。公开页面仍然只读取 Cloudflare Static Assets，缓存未命中也不会查询 Supabase 或 R2。

## 自动分档

服务器本地 Umami PostgreSQL 每 15 分钟汇总 PriceMapAI 最近 24 小时事件，只发送 `{id, clicks}` 和汇总时间。`clicks` 是每家商家的不同 `session_id` 数量，涵盖购买、商家首页、API 原站和中转站详情事件。不会发送会话标识、IP、访问路径、邮箱或管理员密码。订阅商家的 ID 保持域名 + 店铺路径；API 商家使用公开站点 ID。

首份新鲜报告立即应用；之后 Supabase 每小时应用一次策略，最多 20 家订阅商家、5 家中转站进入 10 分钟档，要求至少 3 个不同会话。订阅商家其他档位：最近一天价格/库存状态发生变化为 15 分钟；有点击为 30 分钟；新来源或无点击为 60 分钟；创建超过 7 天且近期无变化、无点击为 180 分钟。API 有点击为 15 分钟，无点击为 60 分钟。失败来源进入恢复档，沿用现有失败退避。热度报告超过 2 小时即不用于提速。

后台有“根据访问热度与采集状态自动调整间隔”开关；关闭后尊重固定间隔。当前采集适配器读取整家商店，并非逐个热门商品抓取。这个实现将 Umami 兴趣自动用于商家调度；PriceAI 的统计运营建议和固定热门商品验证器不应被描述为同一个自动算法。会话去重、热点上限和最低间隔限制成本，但不能证明统计绝不会被伪造。

## 增量与公开发布

1. `export_snapshot_batch` 在数据库内读取公开数据，与私有导出镜像比较。订阅报价正文与按商家共享的采集时间分离；不完整采集中未重新看到的报价保留自己的原时间，不能被商家心跳延长有效期。中转站不输出前端会重新赋值的内部 `lastVerifiedAt` / `lastUpdatedAt`，嵌套报价使用路径补丁。
2. 一个事务保存镜像、递增版本和未确认批次。发送失败时重复返回同一批次。新增、变化、停用和删除均进入批次；每天一次完整检查点，或在版本断档时恢复完整检查点。
3. `publish-snapshot` 每分钟发送批次到独立同步 Worker，不下载 R2 或重新上传整份 JSON。保留旧全量分支作为显式回滚途径。
4. 外层 Worker 只验证凭据并转发；SQLite Durable Object 串行执行合并、压缩和上传，避免普通免费 Worker 的 10ms CPU 限制。同一实例内的异步任务也按 Promise 队列串行处理。
5. 私有 R2 桶 `pricemapai-snapshot-workspace` 只保存 `working/latest.json`，不绑定公开域名、不开放 r2.dev。R2 检查点写入成功后才确认批次；DO 仅保存小型发布状态和热度报告，没有 D1，也没有每条报价的 DO 存储写入。
6. 最多每 5 分钟发布一次完整静态 JSON，没有变化就不重新发布。沿用版本目录、gzip 分页、60 秒清单缓存及当前/上一版保留；所有资源上传成功后才切换静态目录。R2 成功但静态发布失败时不确认，重试安全地继续发布上一检查点。

同步地址 `https://pricemapai-snapshot-sync.newbee.workers.dev` 只允许认证 POST；它没有公开读取报价的路由。访客静态服务 `pricemapai-public-snapshots` 的 workers.dev 仍关闭。热度 `/heat` 使用独立 `UMAMI_HEAT_TOKEN`，不能调用 `/sync` 或 `/status`。现有 `CRAWLER_TOKEN` 不存到 Umami 服务器。

## 额度与失效行为

- 三个 Supabase 函数每分钟一次：30 天基础约 129,600 次，未含手动调用和重试；与组织其他项目共享函数额度。
- SQL 出站预算每日最多 40,000,000 字节，包含完整检查点和重复发送。按 30 天是每段 1.2GB；考虑数据库 → Edge 和 Edge → Cloudflare 两段，保守预留约 2.4GB/月。其他 Supabase 操作仍需单独观察实际用量，这不是总账号流量硬限额。
- 超预算保留待确认批次、暂停传输，次日继续同一批次，保留上一版公开数据；页面按照采集过期时间显示失效状态，不转而查询数据库。
- R2 和 DO 使用量主要随更新批次增长。R2 免费额度与账号其他桶共享，超额可能计费；静态资产读取不增加 R2 操作。DO 采用免费可用的 SQLite 后端。
- 没有新 Cloudflare Cron，不用 Pages 构建钩子，不用 GitHub Actions，不保存 Umami 管理员密码。

## 配置与验证

数据库迁移 `202610100001` 至 `202610100006`，包含首次热度立即应用、预算暂停后续传、仅导出 RPC 的 30 秒查询上限（默认 API 8 秒不足）；旧公开快照迁移原来与 transit_adapters 重用了 009，已改为 010 并将生产已存在的迁移记录标为已应用，避免重复执行。

Cloudflare `wrangler.sync.jsonc` 需要三个 Secret：`CRAWLER_TOKEN`、`CLOUDFLARE_SNAPSHOT_API_TOKEN`、`UMAMI_HEAT_TOKEN`。凭据只放平台 Secret 和 Git 忽略的本地文件。发布凭据是账号级 Workers Scripts Edit，不能描述为只有单个 Worker 权限。Supabase 配置 `SNAPSHOT_SYNC_URL` 后走增量分支。正式切换在首次公开发布验证成功后将 `pricemapai-publish-snapshot` 改为每分钟。

Umami 服务器安装 `deploy/umami/collection-heat.py` 与同目录 service/timer；配置 `/opt/umami/collection-heat.json` 格式为 `{ "endpoint": "https://pricemapai.com/api/collection-heat", "token": "专用令牌" }`，root 所有、权限 600。无配置时只执行只读汇总预览。首次启用需要完成浏览器凭据保存确认。

腾讯云访问 workers.dev 超时，因此热度通过本站 `/api/collection-heat` 和 Service Binding 转发到同一 `/heat`；只接受 POST，无法选择同步或状态路由，接收端照常验证专用令牌。上报声明 `PriceMapAI-Collection-Heat/1.0`，避免 Python 默认客户端被边缘拒绝。

验证命令：`npm test`、`npx supabase db query --linked --file tests/incremental-database.sql`（事务回滚，不留模拟热度）、`npm run build`、`npx wrangler deploy --config wrangler.sync.jsonc --dry-run`、`npx tsx scripts/verify-incremental-sync.ts`。最后一个命令会执行真实同步；首个完整批次还核对生成的静态快照版本，成功才确认批次。

回滚：先恢复发布 Cron 为每 15 分钟，再删除 Supabase 的 `SNAPSHOT_SYNC_URL` Secret，函数回到原全量发布。自动调度可在后台按来源关闭。不要删除 R2 检查点或导出镜像来回滚。

## 生产验收（2026-10-10）

- bootstrap：7,936,304 字节，4,697 条订阅报价、27 家中转站；完整导出的内容 hash 与公开版本一致。
- 无变化增量：118 字节；一次实际变化批次：590,670 字节、43 项变化。这些是不同时间的样本，不能直接推算每月固定流量。
- 腾讯云服务日志返回 `sent: 2` / `received: 2`；定时器已启用，配置 root:root、600。Supabase 在 01:42 UTC 接收并应用报告，小久进入 warm / 30 分钟；中转站单独按其公开 ID 匹配。
- 预算是防止出口无限增长的保护，达到预算会造成报价变旧；免费额度是否足够仍取决于实际变更量和组织其他项目用量。

## PriceAI 字段对照与购买意向排序

参考 PriceAI `b3092c` 的 `src/lib/data.ts`：行为监测覆盖商品详情（`product_id/platform`）、平台页详情（相同字段）、购买点击（`source_id/available`）、平台筛选（`platform`）、范围切换（`scope/platform`）。本站已采集这些事件；PriceAI 当前真正用于商家热度的属性白名单仅为 `purchase_link_click:source_id`，并结合采集年龄、健康状态、连续失败展示热门陈旧和失败来源。不能把所有行为字段都说成它已用于自动调度。

本站额外汇总 `purchase_clicks`、`shop_clicks`、`pricing_clicks`（API 原站首页和报价外链）、`detail_views`。各项分别按不同会话去重；同一会话可以出现在多项，总关注 `clicks` 则是四类事件的去重并集，不等于四项之和。热门资格仍为至少 3 个会话；符合资格的来源按购买×3 + API外链×2 + 首页 + 详情排序，再按总关注和 ID 稳定排序。旧报告兼容按总关注排序。首次扩展字段报告立即应用，之后仍每小时调整。

管理员来源列表显示各项计数、报告时间与有关注但采集待更新的提示。`/api/admin/collection-heat` 使用既有管理员认证，统计不进入公开报价 JSON。即使报价出站预算暂停，发布函数仍通过小型状态请求取得热度并更新调度。商品详情和平台字段保留在统计工具里；目前采集单元仍是整家商店，不将一次商品详情打开扩散成对所有售卖它的商家提速。
