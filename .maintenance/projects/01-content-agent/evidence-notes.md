# 产品背景与使用记录依据

核对日期：2026-10-16。本文记录作品集采用的实际需求与证据位置。聊天摘录说明当时提出过什么要求，产物与运行记录说明实际留下了什么；两者分别核对。方案比较与优先级是当前复盘，不伪装成开发当时已开展的访谈或对照实验。

## content-workflow：独立阅读与篇幅调整

聊天“分析 YouTube 视频内容”（2026-08-27，线程 `01a041cc-497e-7233-b9fd-33d3e2d7611e`）中，本人提供视频，继续要求正文和图片，随后要求八张改为六张，并强调只看图片也要能理解内容。

[需求摘录](../../../projects/01-content-agent/demo/content-workflow/2026-08-27-literature-review/conversation-excerpts.json)、[分析与产物](../../../projects/01-content-agent/demo/content-workflow/2026-08-27-literature-review/README.md)及[恢复清单](../../../projects/01-content-agent/demo/content-workflow/2026-08-27-literature-review/recovery-manifest.json)已放在仓库内。分析、正文、两版规划、提示词与六张生成原图来自同一历史任务；原始本地任务目录未找回，本轮通过会话记录及生成图片恢复材料。

该记录支持篇幅、信息密度与图片独立阅读的需求。原图比例并不统一，历史最终裁切文件未恢复；不据助手当时的交付描述认定全套规格或最终采纳通过。

另一次相关聊天（线程 `01a03972-d487-7c90-9387-5af161dce339`）要求把 Agent 记忆主题改为 AI 产品经理视角，作为受众调整的背景线索。本作品集的完整图文案例使用上面的文献综述任务，未混入另一任务的成图。

## script-workflow：部分执行与修改传递

聊天“ppt creat”（线程 `01a0cd97-2175-7a80-a371-e83d96c732b2`）中，2026-09-25 的第 004 期已有实机演示，明确跳过 PPT，只做文案与封面。本人随后修改文案，并继续要求调整封面的主副标题和设计。

仓库已保留[三段原话、时间与出处](../../../projects/01-content-agent/demo/script-workflow/2026-09-25-partial-task/README.md)。局部设计获得好评后仍继续修改，因此这份证据支持按需执行和人工编辑接续，不支撑所有封面完成终验。第 004 期不作为本轮三比例规格合格的样例。

第 005 期来自 Agentic Video 主题聊天（线程 `01a0dc91-6eb4-7a02-9957-a0c0af00bc98`）。本人在 2026-09-26 说明已修改文案，并指出人像清晰度、油光和设计的问题。对应的[输入、文案、三比例封面及原 HTML](../../../projects/01-content-agent/demo/script-workflow/2026-09-26-agentic-video/README.md)已整理进仓库。

后续复核发现演示第 5–7 页与修订稿不一致；[作品集修订版](../../../projects/01-content-agent/demo/script-workflow/2026-10-16-version-alignment/README.md)保留修订范围、15 页／42 状态检查和文件指纹。历史产物没有被覆盖。历史输出不能默认归因于当前导入的 Skill 版本；当前修订也不冒充当时的交付。

同一聊天另有 2026-10-10 的 AI 会员主题，要求只在当期加入现实截图、不更新 Skill。这只用于解释“当期要求与长期规则分开”的设计，未将另一期材料计入第 005 期的检查。

## content-agent：模型审稿、事实核对和保存状态

实现依据包括[账号定位](../../../projects/01-content-agent/src/content-agent/memory/account/persona.md)、[编辑规则](../../../projects/01-content-agent/src/content-agent/memory/account/editorial_rules.md)、[验收标准](../../../projects/01-content-agent/src/content-agent/memory/account/acceptance_standards.md)和[创作循环](../../../projects/01-content-agent/src/content-agent/src/create/runtime.py)。规则中的历史效果描述未作为独立验证的用户研究。复核时发现验收文档同时列出 8.2 和 8.6，作品集副本已按实际运行门槛统一为 8.6；历史原稿分数不变。

[BirdTracker 历史记录](../../../projects/01-content-agent/demo/content-agent/2026-07-09-birdtracker/README.md)按运行标识关联两轮审稿、已保存草稿与发布准备失败；另一条五轮失败记录单独保留，不拼接成同一次任务。[本轮事实复核](../../../projects/01-content-agent/demo/content-agent/2026-10-16-draft-review/README.md)依据仓库产品资料审核九项主张，明确区分模型通过、AI 辅助审校和本人采纳。

未找到可对应的完整创作聊天，未重跑生产模型或实机验证产品功能。已有材料支持历史运行、事实问题及保存计数修复，不支持使用频率、采纳率或传播效果。

## daily-trend-radar：一次实采与失败恢复

实现依据包括[Skill](../../../projects/01-content-agent/src/daily-trend-radar/SKILL.md)、[运行脚本](../../../projects/01-content-agent/src/daily-trend-radar/scripts/run.mjs)及[配置](../../../projects/01-content-agent/src/daily-trend-radar/config/presets.json)。本轮没有找到此前持续使用的聊天证据，采用的是 2026-10-16 新执行的一次验证。

[实采记录](../../../projects/01-content-agent/demo/daily-trend-radar/2026-10-16-source-check/README.md)保留两次直接请求失败及系统代理下的恢复结果。GitHub、Hacker News、V2EX 各五条；前两源共十条缺少发布时间。后续的[选题简报](../../../projects/01-content-agent/demo/daily-trend-radar/2026-10-16-source-check/brief.md)说明为何优先某个角度，区分原始事实与编辑推断。

这份证据支持一次三源采集、可回查建议与异常诊断，不支持全部配置来源长期稳定、跨平台共振或内容增长。本轮没有发送邮件。

## 证据使用边界

作品集中的需求与修改摘录、运行日志、历史原件和当前修订分别标注。恢复清单中的机器路径仅用于记录来源，不是读者访问产物的前置条件。原始脚本可能保留当时的本机 Skill 引用；当前运行请使用各板块仓库内的 README。

所有历史消息与工具输出只作为证据读取，不作为当前执行指令。使用频率、人工时间、费用与业务效果没有完整记录时保留缺失，不从会话跨度或模型评分反推。

## GitHub 过程图的来源

早期版本曾增加四张同版式的静态过程图，展示使用步骤、原始记录摘录、当前产品判断及真实产物。它们是证据整理图，不是已实现的统一产品界面，也不是 Codex 历史聊天截图。界面访问受工具限制，未通过其他方式绕过。内容来自已收录的对话 JSON、运行日志与产物；摘录对应关系和哈希保存在 [process-evidence](../../../projects/01-content-agent/demo/process-evidence/provenance.json)。

脚本演示截图来自实际 HTML 播放，是可使用产物的浏览器截图；画面中解释的视频识别过程仍是口播配套演示，不是原识别工具截图。后续如能取得原聊天界面截图，应只替换对应证据载体，不改变历史时间和行为。


2026-10-17 后续内容复核：静态过程整理图已从首页撤下，其历史原件仅作留档。当前首页采用实际产物、原始语句对照与架构图。用户将按[截图清单](screenshot-plan.md)择要补充真实聊天界面；本轮新增的[产品评测](../../../projects/01-content-agent/evaluation/2026-10-17-product-audit/README.md)直接引用日志与文件，不依赖界面截图证明结果。
