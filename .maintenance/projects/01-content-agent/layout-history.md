# 历史目录与材料组织记录

## 8. 项目材料归属

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

## 9. 来源与历史迁移

| 迁移前路径 | 当前路径 |
| --- | --- |
| workflows/social-content-skills/ | src/content-workflow/ |
| workflows/script-workflow/ | src/script-workflow/ |
| workflows/content-agent/ | src/content-agent/ |
| tools/daily-trend-radar/ | src/daily-trend-radar/ |

sources.json 的 path 已指向当前真实目录；repo、commit、tree 等来源字段保持原始语义。迁移后重新执行了现有离线测试与 CLI 检查，结果见本轮结构验证记录。目录迁移阶段未改执行逻辑。后续作品集副本新增交接检查，并修复雷达失败报告、内容 Agent 保存计数及审改提示；原仓库未改，差异已登记在 sources.json。
