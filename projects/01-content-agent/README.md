# 内容生产 Agent 与 Skill 工具链

本项目组汇集围绕内容生产的六个工程：从素材获取、热点研究到文案、图片和 HTML 演示产物。当前保留各工程独立运行方式，尚未验证它们已经组成统一平台。

作品集关注的问题是：哪些步骤适合确定性工具，哪些需要模型判断；如何约定产物、处理失败，并让能力被复用。

## 工程导航

| 工程 | 已有材料与实现线索 |
| --- | --- |
| [social-content-skills](src/seedxdream--social-content-skills/README.md) | YouTube 字幕优先获取、Whisper 降级、分析及图文输出 Skill |
| [content-agent](src/DualAries-1--content-agent/README.md) | 研究、写作、审稿、改稿、结构化日志，以及发布模块 |
| [daily-trend-radar](src/DualAries-1--daily-trend-radar/README.md) | 多源榜单获取、结构化结果、来源状态与失败说明 |
| [script-to-html-slides](src/doublegou--script-to-html-slides/README.md) | 口播脚本到 HTML 演示、播放状态与产物检查 |
| [script-to-post](src/doublegou--script-to-post/README.md) | 口播脚本到标题和短描述，编号与文件检查 |
| [script-to-image](src/doublegou--script-to-image/README.md) | 文案到三种比例封面，尺寸和编码检查 |

## 两条核心工作流

1. YouTube URL → 字幕获取／转写降级 → 内容分析 → 正文与图片 → 人工验收。
2. 本人口播脚本 → HTML 演示；脚本 → 发布文案 → 三比例封面 → 文件与视觉验收。

热点雷达作为选题输入补充。content-agent 是相关的程序化实现，是否替换或整合 Skill 链路，要根据实际使用关系再决定，不虚构统一版本演进史。

## 本人的角色

简历记载了内容 Agent 的需求拆解、Skill/Workflow 重构及核心链路开发。六个工程逐项对应的个人职责、协作情况和时间线待本人确认，暂不将全部来源内容声明为独立原创。

## 案例与证据

- [设计复盘与待补决策](docs/case-study.md)
- [验证方案](evaluation/README.md)
- [演示脚本](demo/README.md)

简历中的 50+ 次运行、15 次转写兜底、Token 降低约 60% 和内容耗时变化尚未在本轮复核，不作为新完成的评测结论。宿主 Agent 提供的调度和运行能力也不计为自研 runtime。

## 运行边界

从各工程 README 进入，不存在统一启动命令。content-agent 的部分入口默认会发布内容；未来演示只生成草稿，应显式使用其 `--no-publish` 模式，并在运行前核查入口行为。此次没有执行发布或外部账号操作。
