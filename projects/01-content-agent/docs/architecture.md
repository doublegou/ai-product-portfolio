# 内容生产项目顶层设计与建设规划

更新日期：2026-10-16。

状态：已按本设计完成目录迁移与 content-workflow 命名，四份板块的产品设计首稿、演示指南与验收方法已落地。现已补入四个板块的真实材料、修订和验证；长期业务效果仍待测量；全部入口见[项目 README](../README.md)。

## 1. 项目定位与组织原则

这是独立完成的内容生产项目组，包含三条工作流和一个独立热点工具。作品集需要呈现从问题、方案到实现、验证和迭代的完整过程。

项目级以 README、docs、demo、evaluation、src 组织；四个板块在这些材料中使用相同名称，便于分别完善和交叉查证。源码仓库数量不决定案例数量，不强行合并不同业务逻辑，也不把尚未接入的能力画成已完成的公共服务。

## 2. 四个板块与边界

| 统一名称 | 任务与交付 | 实现与依赖 |
| --- | --- | --- |
| content-workflow | YouTube 视频 → 中文分析、小红书正文、系列卡片 | yt-analysis 生成 analysis.md；note-writer 与 note-images 独立读取；字幕缺失时经确认后转写 |
| script-workflow | 本人口播稿 → HTML 演示、发布标题短描述、三比例封面 | 演示与文案分别读取原稿；封面继承文案；PPT 与 post 编号独立 |
| content-agent | 自有产品资料与账号规则 → 选题研究、写作、审改、草稿与发布处理 | Python 控制流程；另有长期策略研究，人工确认后更新记忆 |
| daily-trend-radar | 多源榜单 → 带来源状态的报告与选题建议 | Node.js 采集与 Agent 分析；尚未自动接入其他三个板块 |

content-workflow 是用户指定的新名称，当前范围仍是 YouTube 转图文，不因名称变宽而宣称支持所有内容渠道。三个内部 Skill 名称保持不变。原仓库 seedxdream/social-content-skills 保留在来源追溯记录中，远端地址不改。

content-agent 不是整个项目组的总调度器。其内部热点采集与 daily-trend-radar 有重叠，但来源范围和数据结构不同；复用作为后续具体方案评估，不在本轮目录调整中顺带实现。

## 3. 当前目录

```text
01-content-agent/
├── README.md
├── docs/
│   ├── architecture.md
│   ├── case-study.md
│   ├── evidence-notes.md
│   ├── content-workflow.md
│   ├── script-workflow.md
│   ├── content-agent.md
│   └── daily-trend-radar.md
├── demo/
│   ├── README.md
│   ├── content-workflow/
│   ├── script-workflow/
│   ├── content-agent/
│   └── daily-trend-radar/
├── evaluation/
│   ├── README.md
│   ├── run-template.csv
│   ├── content-workflow/
│   ├── script-workflow/
│   ├── content-agent/
│   └── daily-trend-radar/
└── src/
    ├── content-workflow/
    │   └── skills/
    │       ├── yt-analysis/
    │       ├── note-writer/
    │       └── note-images/
    ├── script-workflow/
    │   ├── script-to-html-slides/
    │   ├── script-to-post/
    │   └── script-to-image/
    ├── content-agent/
    └── daily-trend-radar/
```

树中源码内部只展示关键节点，原工程的资源、文档、测试和历史数据保留。四份板块设计已包含范围、流程、取舍和实现依据；demo 与 evaluation 各板块已有具体任务指南和验收方法，真实任务目录及本轮结果表现已建立，范围见 evaluation/release-review.md。此前 refactor-check.md 保留为历史记录，本轮检查见[structure-check.md](../evaluation/structure-check.md)，均不算业务效果。

## 4. 各层分别完善什么

| 位置 | 内容 | 与其他材料的关系 |
| --- | --- | --- |
| 项目 README | 一句话定位、四个板块、重要结果、当前阶段和阅读入口 | 招聘方的独立阅读入口，链接案例与代表性产物 |
| docs/architecture.md | 本文：整体范围、板块关系、材料归属与推进顺序 | 定义建设规则，不重复各板块详细设计 |
| docs/evidence-notes.md | 实际使用记录、实现依据、当前本地线索与核验边界 | 支持设计追问；不替代完整演示与效果测量 |
| docs/case-study.md | 整个内容生产案例的主线、代表性取舍、结果和限制 | 从四个板块提炼，链接具体证据，不复制四篇文档 |
| docs/<板块>.md | 用户任务、原流程痛点、首版范围、输入输出、过程与失败分支、方案比较、实现状态、迭代记录 | 需求与设计先写在一份文档中，复杂到影响阅读时再拆分 |
| src/<板块>/ | Skill、程序、资源、配置与工程测试 | 实现与运行说明随代码维护 |
| demo/<板块>/<任务>/ | 同一真实任务的输入、最终产物、必要截图或录屏 | 供演示与评测共同引用，不把不同任务产物拼成一次运行 |
| evaluation/<板块>/ | 验收标准、样本条件、运行记录、结果、失败分析与结论 | 引用 demo 的任务及代码版本，不再复制整套产物 |

四个板块统一使用表中名称作为目录名、文档名和新评测记录的 workflow 值。原方案中的 youtube-social、script-assets、product-content、trend-radar 是旧别名；说明已更新；若发现真实历史记录则保留原值并说明映射。

同一任务通过任务标识、明确路径和版本关联。script-workflow 的 task 标识不改变原有 PPT/post 编号规则。未能取得的费用、耗时和历史事实留空或标注待补。

## 5. 四个板块的完善重点

| 板块 | 产品与设计重点 | 演示重点 | 验证重点 |
| --- | --- | --- | --- |
| content-workflow | 视频改编需求、共享分析与独立创作、字幕降级和人工检查 | 一条视频从输入到图文，以及真实降级或修订过程 | 分析覆盖、事实准确、图文一致性、人工修改、耗时与成本 |
| script-workflow | 口播顺序、三种产物的边界、文案对封面的约束、独立编号 | 同一期脚本与演示、文案、三比例封面 | 播放行为、文字正确、比例与视觉一致性、修改轮次和费用 |
| content-agent | 产品与账号约束、选题和写作研究、审改循环、策略更新 | 草稿生成与审改，历史失败及其处理 | 产品事实、人工采纳、研究条件、审改上限、失败重试成本 |
| daily-trend-radar | 来源选择、时间语义、事件归并、部分失败处理 | 来源状态与可追溯报告 | 实时来源可用率、归并准确性、链接与时间正确性、降级行为 |

这些是待完善的工作方向，不是已验证成果。四个板块不强制用同一套指标，也不合成一个总成功率。

## 6. 实施顺序与验收

1. **落实结构和命名（已完成）。** 按下表迁移，更新引用、来源路径和评测名称；保留源提交与已完成的本地修订。验收是文件完整、路径可解析、受影响工具正常。
2. **补齐产品设计（首稿已完成）。** 四份文档说明场景、问题、目标、范围、方案比较、异常和验收；已结合聊天中的实际需求，依据见 [evidence-notes.md](evidence-notes.md)。历史动机不强求恢复，方案理由按当前产品复盘表达；使用频率和收益等待实际证据。
3. **用真实任务补证据。** 先核对历史产物与日志，再为选定工作流准备完整任务；保存实际输入输出及失败处理，并按该板块标准测量。四个板块分别采用与实际输入关联的任务，保留各自结论与限制。
4. **根据结果迭代。** 先明确问题与验收条件，再改代码或 Skill；复测相关场景，将结论回写板块文档。
5. **形成展示案例。** 在 case-study.md 与项目 README 提炼关键判断、结果、演示和限制。详细材料留在各自位置，总 ROADMAP 跟踪进度。

## 7. 已完成的目录迁移

| 迁移前路径 | 当前路径 |
| --- | --- |
| workflows/social-content-skills/ | src/content-workflow/ |
| workflows/script-workflow/ | src/script-workflow/ |
| workflows/content-agent/ | src/content-agent/ |
| tools/daily-trend-radar/ | src/daily-trend-radar/ |

sources.json 的 path 已指向当前真实目录；repo、commit、tree 等来源字段保持原始语义。迁移后重新执行了现有离线测试与 CLI 检查，结果见本轮结构验证记录。目录迁移阶段未改执行逻辑。后续作品集副本新增交接检查，并修复雷达失败报告、内容 Agent 保存计数及审改提示；原仓库未改，差异已登记在 sources.json。
