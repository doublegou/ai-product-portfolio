# PriceMap AI · 正式项目

由最新 `pricemapai_web_design` 前端与自有 `aimarketing` Worker、采集器、管理页和数据库迁移组合而成。技术栈为 React + Vite、Cloudflare Workers Static Assets、Supabase Postgres / Cron / Edge Functions。2026-10-09 已完成建表、原站首轮采集和 Cloudflare 正式部署。

线上地址：<https://pricemapai-web-production.pricemapai.workers.dev>。目前按用户要求使用默认域名，自有域名稍后再绑定。Supabase 项目为 `uoxeyzowhonxcpcijsbr`。

管理入口：[生产后台](https://pricemapai-web-production.pricemapai.workers.dev/admin)。填写 `ADMIN_TOKEN` 登录，无独立用户名；进入后可选择卡网订阅或 API 中转站，管理来源、试采集、手动采集和查看日志。令牌只保存在页面内存，刷新后需要重新登录。真实密钥通过 Cloudflare / Supabase 的 Secrets 配置，本地 `.dev.vars` 已排除出 Git。

代码仓库：`seedxdream/pricemapai-web-production`（私有）。测试与构建命令为 `npm test`、`npm run build`；推送代码不会自动部署，部署步骤见下文。 自动测试工作流保存在 `docs/github-actions-quality.yml`，由于本次 GitHub 命令行授权不含 `workflow` 权限，尚未启用 GitHub Actions。以后可通过 GitHub 网页将该模板保存为 `.github/workflows/quality.yml`，或在具备工作流写入权限后提交该路径。

2026-10-09 本次对照 PriceAI 的 699 条商家记录，得到 664 个可识别的去重店铺地址。原有 236 家来源只对应其中 218 个地址；现已核验并新增 138 家原站，总登记来源 374 家，另确认 2 个已有来源的地址别名。306 个参考地址仍受原站故障、采集限制、迁移或接口待适配影响，逐条记录在 [覆盖核验报告](docs/merchant-coverage.md)，没有用参考站报价补齐。登记数与云端当前成功数不同，后台采集日志保留每家实际结果。API 中转站已独立接入，详见 [API 生产接入](docs/transit-production.md)。

## 本地运行

Node.js 22.12+，安装依赖：

```sh
npm ci
```

只查看现有设计与我们自己采集的订阅历史快照：

```sh
npm run dev:design
```

这是明确标记的本地预览，沿用快照采集时刻判断有效期。生产构建始终排除该快照和演示报价。

连接自己的 Supabase 后运行完整服务：

```sh
cp .env.example .dev.vars
# 在 .dev.vars 填写 Supabase URL、后端密钥和随机管理令牌
npm run build
npm run worker:dev
```

Worker 地址为 `http://127.0.0.1:8787`，包含网站、`/api/offers`、`/api/history/:id`、`/api/transit` 和 `/admin`。修改前端时，在另一个终端运行 `npm run dev`，Vite 将 `/api` 代理至该 Worker。未配置数据库时 API 返回 503，页面显示连接状态，不以样例价格替代。

## 数据来源与映射

1. PriceAI 可以作为店铺发现参考，提取待核验的店铺原站地址。
2. 已有 374 家店铺的原站配置保存在 `config/verified-sources.json`。同平台不同店号分别保存，来源唯一键为完整 `base_url`。
3. 采集器从配置中的原站地址读取标题、SKU、价格、库存和购买链接。采集接口限定为该来源同域；不会向 PriceAI 请求商品或报价。
4. `worker/classify.ts` 提取字段；`complete_crawl` 按 `(source_id, external_id)` 更新已有报价并记录价格/库存变化。
5. Worker 返回现有前端 Offer 字段；前端继续使用既有商品映射与筛选逻辑。

原始 SQL 种子中的 AI智充、西瓜小铺原先未出现在 JSON 清单中，本次已将两者补入，方便通过一份来源配置初始化。

API 中转站已核验 28 家候选原站，27 家已配置独立采集器、数据库、管理入口和调度，共 3,185 条报价；剩余 BMCCA 原站未启用公开报价，监测接口要求登录。外层目录已显示站点或公开分组/模型汇总监测。报价与监测全部来自商家原站。官方 API 目录及官方定价链接保留。操作、映射规则与边界见 [API 生产接入](docs/transit-production.md)。

## 原站采集与写库

试采集指定店铺，不需要数据库，也不会写库：

```sh
npm run collect -- --source https://gospv.com/
```

来源初始化默认只检查配置；显式 `--write` 才连接 `.dev.vars` 指定的库并导入来源：

```sh
npm run sources:import
npm run sources:import -- --write
```

正式采集一个已入库的来源，或领取一批到期来源：

```sh
npm run collect -- --source https://gospv.com/ --write
npm run collect -- --due --write
```

首次上线时，为尚未采集过的来源各采集一次（最多同时处理两家，已失败来源仍遵循其重试计划）：

```sh
npm run collect -- --initial --write
```

CLI、管理页与 Cron 共用采集器、分类、数据库租约和写入事务。失败保留旧数据；只有完整快照才下架消失商品；未知库存不推测为有货。管理页也支持保存前试采集。

## 数据库与部署

本次已连接目标项目并执行八个迁移。之后新增迁移时继续使用同一流程：

```sh
npx supabase login
npx supabase link --project-ref uoxeyzowhonxcpcijsbr
npx supabase db push
npm run sources:import -- --write
```

迁移保留 `aimarketing` 的原始版本号，便于已有数据库继续使用；新数据库按顺序执行。种子不会自动运行；初始化来源使用上面的导入命令。旧 Supabase HTTP 采集任务会被后续迁移停用，保留每日日志/历史清理。若复用旧库，应停用旧调度，只保留本项目的两个 Supabase 采集任务，避免重复调度。

```sh
npx wrangler login
npm run deploy:check
npx wrangler secret bulk .dev.vars
npm run deploy
```

Worker 名称固定为 `pricemapai-web-production`，配置绑定本次登录的 Cloudflare 账号，未沿用旧项目账号。后端密钥和管理令牌已通过 Worker Secrets 配置；本地 `.dev.vars` 不纳入 Git。管理页为 `/admin`，从本地 `.dev.vars` 获取管理令牌，不要把该文件放入网站静态目录。

当前所有启用来源统一目标每 15 分钟采集；Supabase Cron 每分钟检查队列，直接调用同项目的 `collect-prices` Edge Function 执行实际抓取和写库。Cloudflare 负责网站、查询 API 和管理入口，采集 Cron 已停用。每批最多 64 家，4 家并发，同域请求间隔至少 500 毫秒。原先 6／21／209 家、60／360／720 分钟和每批 8 家的配置已经替换；这些是历史导入批次设置，并非产品要求。

采集函数共享 `worker/crawl.ts` 与原站解析器，使用数据库租约防止重复采集。每个来源最多采集约 50 秒；批次运行 70 秒后停止领取新工作并归还未开始任务，避免超出免费函数运行时长。正常来源在采集完成 15 分钟后再次到期，排队与网络耗时会带来偏差；失败退避最长 4 小时。45 分钟未成功确认的报价标为过期，不参与最低价；错误不会覆盖上次真实报价。采集日志保留 3 天，变化历史保留 30 天，减少免费数据库空间消耗。

`supabase/functions/collect-prices` 需要部署到同一 Supabase 项目，并设置一个随机 `CRAWLER_TOKEN` Secret，与 Worker Secret 中同名值一致。函数保留 JWT 验证，另外校验这个调用令牌；数据库后端密钥使用 Supabase 函数自带环境变量。Cloudflare 的 `CRAWLER_FUNCTION_URL` 在 `wrangler.jsonc` 中配置。后台手动采集仍通过该地址调用函数。定时任务从 Supabase Vault 读取调用凭据，只允许数据库管理员执行调度函数，不向浏览器开放。凭据只放本地忽略文件、平台 Secret 和 Vault。

```sh
npx supabase functions deploy collect-prices --project-ref uoxeyzowhonxcpcijsbr --use-api
npm run crawler:schedule:configure # 将当前 .dev.vars 中的采集凭据写入已关联项目的 Vault
npx supabase db push --linked # 006 迁移启用每分钟任务；在配置凭据后运行
# 更新采集代码时需要同时重新部署以上函数；前端部署仍用 npm run deploy。
```

网站和定时任务均在云端运行，关闭本地开发服务器不影响服务。

## 页面更新

订阅页打开时请求 `/api/offers` 并读取全部分页，每 5 分钟及重新聚焦时更新。只有完整读取成功才替换页面数据；刷新失败保留上次结果并提示重试。页面使用每条报价的 `last_seen_at` 展示采集确认时间，不将 API 请求时间作为报价时间。库存通过 `raw_data.stock_quantity` / `stock_text` 映射：有明确件数显示件数，仅公布文字时沿用原站文字，未知与过期均明确说明。

## 验证与目录

```sh
npm test
npm run build
npm run deploy:check
```

本次已通过 68 项测试、TypeScript 检查、生产构建、云数据库事务测试，并验证线上 API 的全部分页、库存字段和实际批量采集结果。线上 `/api/health` 返回正常，未授权管理请求返回 401。事务测试只在回滚事务内创建临时数据。

- `src/`、`public/`：最新设计与运行时数据接入。
- `worker/`：查询 API、管理 API、原站采集。
- `scripts/`：来源导入与原站采集命令。
- `supabase/`：数据库迁移、采集 Edge Function 与历史种子。
- `config/`：已接入店铺和待核验中转站。
- `fixtures/`：仅本地设计预览使用的自采历史快照。
- `docs/frontend-baseline.json`：复制时前端文件的哈希，含尚未提交的设计改动。
- `docs/frontend-reference.md` 及其他接入记录：迁移前项目的历史说明，当前行为以本 README 为准。

后台令牌及 Supabase 后端密钥仅用于 Worker、Supabase 函数与本地脚本，不加入前端环境变量。项目没有自动部署 workflow，质量检查只运行测试和构建。

2026-10-09 调度核验发现 Cloudflare 配置保存后仍按旧五分钟触发，因此改用 Supabase 内置 Cron 直接调用采集函数，并清空 Cloudflare 采集定时器。已观察到连续三分钟自动触发，前两轮均返回 HTTP 200、各成功采集 64 家；调度权限检查通过。调度执行与原站结果分别核验，详细结果见 `docs/production-verification-20261009.json`。

本次补收两家明确迁移的原站：大白发卡（19cm.tech → geminipro.vip）和 Desolate（fk.desolate.codes → shop.desolate.run），已在云端采集 5 + 4 条原站报价。剩余 306 个待接通参考地址中，271 个属于链动小铺及旧域名；本地与云端返回存在差异，不能仅凭一次 520 判断为地址错误。详情见 `docs/production-followup-20261009.json`。
