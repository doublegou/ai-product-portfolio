# Quick start

[返回项目](../README.md) · [真实操作演示](../demo/README.md) · [技术方案](technical-design.md)

## 直接体验

打开 [PriceMap AI](https://pricemapai.com)，分别进入订阅和 API 入口。订阅路径查看交付方式、商品说明与原站；API 路径查看具体模型、分组、单位、币种和监测对象。站点为持续变化的线上产品，历史录屏与归档数据以各自日期为准。

## 在本地运行完整页面

需要 Node.js 22.12+（本次验证使用 26.8.1）、npm 和 Python 3.9+。从作品集仓库根目录执行：

```bash
cd projects/04-pricemapai/src/pricemapai-web-production
npm ci
npm run build
python3 ../../evaluation/serve-preview.py
```

浏览器打开 `http://127.0.0.1:4184`。页面使用原生产构建与 2026-10-17 的完整公开快照，包含订阅和 API 两条路径；没有另做一套展示界面。按 `Ctrl+C` 停止预览。

预览服务只绑定本机，不需要 Supabase、Cloudflare 或统计账号。它限定读取归档数据，通过响应策略阻止页面请求外部统计与接口；管理路径不可用，原站链接仍会在主动点击后访问外站。快照没有写入生产 `public/` 目录，也不会自动部署。

**保留真实时间：**随着当前日期推进，历史报价会显示过期；这是正常的有效期行为。需要精确重现采样时的质量计数，请运行下面的固定时间回放，不通过修改页面时钟把旧价伪装成新价。

## 重算质量与验证工程

在上面的源码目录继续执行：

```bash
npm test
npx tsx ../../evaluation/replay-snapshot.mts
```

第一条运行原仓库测试；第二条离线校验 19 个分页的哈希，并使用原生产规则生成 `evaluation/snapshot-replay.json`。每次得到相同采样时点的统计，以及缺页、混版、重复与时间推进的检查结果。

## 阅读代码

| 想了解什么 | 入口 |
| --- | --- |
| 标题怎样归入商品类别 | [worker/classify.ts](../src/pricemapai-web-production/worker/classify.ts) |
| 什么条件下展示同规格最低价 | [src/lib/offers.ts](../src/pricemapai-web-production/src/lib/offers.ts) |
| API 倍率、额度和单位怎样处理 | [worker/transit.ts](../src/pricemapai-web-production/worker/transit.ts) |
| 不完整公开版本怎样被拒绝 | [src/data/snapshot.ts](../src/pricemapai-web-production/src/data/snapshot.ts) |
| 增量发布与预算 | [snapshot/](../src/pricemapai-web-production/snapshot/) |
| 定时采集、租约和数据库事务 | [supabase/](../src/pricemapai-web-production/supabase/) |

生产配置与部署步骤保留在[原始源码文档](../src/pricemapai-web-production/README.md)。本地查阅和离线回放无需执行部署、采集或迁移命令。
