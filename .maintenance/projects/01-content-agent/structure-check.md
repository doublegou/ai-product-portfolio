# 目录迁移阶段验证记录

日期：2026-10-16。此文保存目录迁移时点的检查；后续代码修复和投递改版以[当前验证记录](release-review.md)为准。范围：将第一个项目归回 src/、采用 content-workflow 名称，并建立四个板块对应的设计、演示和评测入口。此前 workflows/、tools/ 阶段另见[历史记录](refactor-check.md)。

## 文件与来源

迁移前保存 239 个文件的 SHA-256、权限或符号链接目标，按新路径逐项核对：无遗漏，权限与链接目标未变。数量为六个来源的 238 个文件，加 script-workflow 组合入口 README；不包含本机依赖和缓存。

本轮源码目录内仅以下四份 README 因名称、运行路径或演示路径变化：

- src/content-workflow/README.md
- src/content-workflow/skills/note-writer/README.md
- src/script-workflow/README.md
- src/content-agent/README.md

其余 235 个文件保持一致，包含业务执行代码、测试、资源及历史数据。来源清单的六项 path 已更新，原 repo、commit、tree 保留；各来源文件均在新路径纳入 Git 变更。旧 workflows/、tools/ 根目录已移除。

本轮不重新查询 GitHub；远端版本沿用同日的[来源核对](../../SOURCE_CHECK.md)。本地文档修订仍在 sources.json 的 portfolio_changes 中记录。未修改原仓库或原本地工程。

## 新路径上的离线验证

以下命令均从 src/ 下对应工程根目录重新执行。脚本组合入口不是独立来源仓库。

| 工程／对象 | 命令 | 结果 |
| --- | --- | --- |
| script-workflow/script-to-html-slides | python scripts/test_tools.py | 6/6 |
| script-workflow/script-to-html-slides | node --test scripts/test_state.cjs scripts/test_audit.cjs | 9/9 |
| script-workflow/script-to-post | python scripts/test_post.py | 9/9 |
| script-workflow/script-to-image | python scripts/test_check_covers.py | 10/10 |
| content-agent | python -m unittest discover -s tests -v | 10/10 |
| daily-trend-radar | npm test | 8/8 |
| content-workflow | python skills/yt-analysis/scripts/youtube_transcript.py --help | 退出码 0 |
| content-workflow | python skills/yt-analysis/scripts/create_workspace.py --help | 退出码 0 |

合计 52 项现有测试、2 项 CLI 检查通过，无跳过。Python 3.14、Node.js 26.8.1；复用隔离环境中的 Pillow 12.3.0、OpenAI Python 3.31.0、python-dotenv 1.2.4、Pydantic 2.14.1，以及按雷达锁文件安装的依赖。本轮未更新依赖。Python 禁写字节码，测试日志通过 CONTENT_AGENT_LOG_DIR 写入临时目录，原历史日志未改。

## 文档与边界

当前项目入口、四个板块设计、演示指南与验收方法已建立互链，总规划、路线图及来源索引同步更新。本轮检查了这些文档、共享作品集文档及改动的源码说明，共 31 份文档、162 个本地链接，全部有效；15 项来源目录均存在，迁移的 239 个文件均已纳入 Git 路径，git diff --check 通过。

content-agent 的模型调用使用 mock，热点雷达检查本地解析、归并及调度；YouTube 只检查 CLI 启动。未执行真实字幕获取、转写、模型生成、图片生成、联网采集或平台发布。工程检查通过不证明内容质量、人工采纳率、耗时收益或费用降低；这些需按[各板块验收方法](../../../projects/01-content-agent/evaluation/README.md)另行测量。
