# API 中转站生产接入

28 家候选地址来源于已有目录；逐站访问公开原站核验后，27 家已有可采集接口，配置保存在 `config/verified-transit-sources.json`。剩余 BMCCA 的公开模型广场未启用，监测接口要求登录，原站证据见 `transit-coverage.json`。不读取 PriceAI 的价格、监测或图片代理，不调用任何付费模型。

## 数据链路

原站公开 ai-transit 快照 / New API pricing / Zivv / OneHop / 模型目录 → Supabase Edge Function `collect-transit` → `transit_sources`、`transit_snapshots`、`transit_crawl_runs` → Cloudflare `/api/transit` → 原有 `/api-pricing` 页面。

当前每站保存一个完整快照，包含原站公开的模型、分组、规格、价格及监测记录。不另造测量数据。成功采集在同一事务内替换当前快照；空响应、解析错误、超时均保留旧报价。以来源 ID + 分组 + 模型 + 规格构成报价标识，避免不同分组被覆盖。

Supabase Cron 每分钟调用 `collect-transit`，每次领取最多 4 个到期来源，2 个并发。正常来源完成采集 15 分钟后到期；失败按 30 / 60 / 120 / 240 分钟退避。3 分钟租约防止重入，迟到的写入拒绝覆盖新快照。15 分钟来源超过 45 分钟未更新标记过期，不参与综合系数排序。日志保留 3 天。

前台首次打开、重新聚焦（至少间隔 1 分钟）和每 5 分钟读取全部分页。只有完整读取成功才替换数据，失败保留上次结果。Cloudflare 缓存最多 5 分钟，浏览器最多 1 分钟；实际可见延迟包含采集排队和缓存。页面显示数据库 `last_seen_at`，原站生成时间另外保留，不以页面刷新时间冒充报价更新时间。

## 价格与监测映射

- token 单价转为每百万 Token，区分 CNY、USD 和 USD 计价额度。只有原站明确公开充值币种与换算且字段一致时，才折算现金价格。
- 原价已经包含分组倍率时不再重复乘倍率；图片不同规格分别保存，固定价保留“每张 / 每次 / 每秒”。
- 多档阶梯和 New API 表达式不执行、不当作平价展示，提示原站档位。缺失价格保留未知，明确零价格保留零。
- 综合系数只用于可核实的 CNY 充值系数 × 原站倍率。不同站点基准可能不同，不能视为所有模型统一折扣；应核对同一模型输入/输出单价。美元、额度、阶梯、已含倍率和过期数据不进入该排序。
- New API 换算依据官方计费规则：1 USD 计价额度 = 500,000 配额；每百万输入 Token = `model_ratio × 2 × group_ratio`，输出另乘 `completion_ratio`。原始倍率不是相对官方价格的折扣。依据：https://docs.newapi.pro/zh/docs/guide/feature-guide/admin/system-setting-advanced
- 监测优先使用对应模型与分组数据。只有分组探测时标出实际探测模型；全站概况不冒用某个模型探测值。未知样本数不虚构，零样本不标 100% 可用；无逐次历史不造图。超过 24 小时的监测或过期报价所附监测显示待更新。
- 外层目录优先展示原站全站监测；没有全站数据时，先按独立分组/模型去重，再按同一时间窗口汇总。有公开样本数时按样本加权，否则等权并明示。报价规格数不影响权重，不把缺失指标当成零。
- 独立监测入口支持 New API 性能摘要、Zivv 渠道状态和星链公开 v2 监测。监测入口失败不会丢失成功取得的价格；错误随快照记录。未公布吞吐时显示“未公开”，不从延迟推算吞吐。
- 缓存和吞吐注明统计范围，TPM / 60 仅表示该范围总吞吐，不能当作单请求生成速度。来源信息为商家公开声明，不表示本站做过付费模型实测。

已确认的匿名公开协议数据入口直接读取，不携带登录态或密钥；其他路径继续检查 robots。默认请求超时 35 秒，贝贝完整快照使用原站 `/api/public/transit/snapshot`，设为 55 秒；配置允许 10–60 秒。OneHop 若出现未处理的下一页，采集失败并保留旧快照，避免写入残缺目录。

## 管理与维护

`/admin` 使用现有 ADMIN_TOKEN，选择“API 中转站”：添加/修改/暂停来源、原站试采集、手动采集、查看日志。密钥只在页面内存中，刷新后重新登录。试采集不写库；配置更改会使旧任务租约失效。

```sh
npm run transit:import                         # 检查27家配置
npm run transit:import -- --write              # 只补充缺少的来源，保留已有配置/暂停状态
npm run transit:collect -- --source=api-1pkapi-com
npm run transit:collect -- --source=api-1pkapi-com --write
npm run transit:collect -- --write             # 领取到期来源
npx supabase functions deploy collect-transit --project-ref uoxeyzowhonxcpcijsbr --use-api
npm run deploy
```

采集代码修改后部署 Edge Function；前台/Worker 修改后部署 Cloudflare。数据库 007 建表及事务函数，008 建独立 API 调度，009 扩展采集器类型，复用已配置的 Vault 凭据。新项目先运行 `npm run crawler:schedule:configure` 配置 Vault；两个采集函数使用相同 CRAWLER_TOKEN Secret。所有新表启用 RLS，浏览器无直接表权限，写入只走后端；调度函数仅 postgres 可执行。正式密钥不进入仓库或静态构建。

## 验证

- `npm test`：包含币种、重复倍率、阶梯价、监测范围、分页失败、过期及管理鉴权测试。
- `npm run build`：类型检查与生产构建。
- `supabase db query --linked --file tests/transit-database.sql`：回滚事务验证租约、失败保留、过期、暂停和访问边界。
- `supabase db query --linked --file tests/scheduler.sql`：调度唯一性与执行权限。
- 扩展接入的当前数量、逐站监测字段和来源状态见 `transit-expansion-verification.json`；原有鉴权/事务验证记录保留在 `transit-production-verification.json`。

- 2026-10-09 浏览器验收：桌面与 390 × 844 响应式视口检查了目录、详情、搜索、排序、分页、官方平台筛选和滚动吸顶；修复阶梯价显示、低可用率颜色和窄屏卡片溢出。后台登录页及无效密钥提示已检查；认证后的管理操作由接口验证覆盖，未逐项进行浏览器编辑。详见 `transit-browser-verification-20261009.json`。
- 本次补接 Codebot、GPTZZZ、MFAPI、旋转智能、天机阁、合聚、OneHop、Zivv、星链，共 27 家、3,185 条报价。贝贝替换公开入口并增加超时后已重新成功；最新数据库检查为 27 家均有成功记录且无当前采集错误。Cron 每分钟触发正常，不代表商家未来每轮都会成功。
- 全量 68 项测试通过；增加超时配置后，16 项采集与映射专项测试再次通过，生产构建通过。

- 扩展接入后公开 API 已核验 25 家可用率、24 家延迟、8 家吞吐；这些数量随商家公开范围和过期状态变化。外层桌面目录及吸顶已验收。电脑随后再次锁定，本次新增商家详情与窄屏复验未完成；此前窄屏验收记录不作为本次新增内容的验收结论。
