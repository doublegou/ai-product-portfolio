# 工作流目录重构验证

> 历史记录：本文记录此前迁入 workflows/、tools/ 的阶段。当前代码已归回 src/，本轮重新检查结果见[结构验证记录](structure-check.md)。下文命令与路径保留其执行时状态。

日期：2026-10-16。验证对象是目录迁移后的本地结构与现有工具，不是端到端内容生成效果。

## 迁移范围

| 原目录（相对本项目） | 当前目录 |
| --- | --- |
| src/social-content-skills | workflows/social-content-skills |
| src/script-to-html-slides | workflows/script-workflow/script-to-html-slides |
| src/script-to-post | workflows/script-workflow/script-to-post |
| src/script-to-image | workflows/script-workflow/script-to-image |
| src/content-agent | workflows/content-agent |
| src/daily-trend-radar | tools/daily-trend-radar |

六个工程共 238 个文件迁移前保存 SHA-256、文件权限或符号链接目标，迁移后逐项校验，无文件遗漏。相对此轮开始前，只有 social-content-skills/README.md、content-agent/README.md 与 content-agent/.gitignore 改动，分别补充本地入口、运行路径和环境忽略规则。业务执行代码、资源、原有测试及历史数据未改变。

新增 workflows/script-workflow/README.md 为三个 script Skill 的组合入口。已移除空的 src/；来源清单和作品集链接同步指向新位置。其他两个项目的源码结构未在本轮继续调整。

## 离线验证结果

| 对象 | 命令（在对应工程根目录执行） | 结果 |
| --- | --- | --- |
| HTML 工具 | python scripts/test_tools.py | 6/6 |
| HTML 播放状态与布局检查 | node --test scripts/test_state.cjs scripts/test_audit.cjs | 9/9 |
| 发布文案工具 | python scripts/test_post.py | 9/9 |
| 封面检查器 | python scripts/test_check_covers.py | 10/10 |
| Python content-agent | python -m unittest discover -s tests -v | 10/10 |
| 热点雷达 | npm test | 8/8 |
| 字幕工具入口 | python skills/yt-analysis/scripts/youtube_transcript.py --help | 通过 |
| 图文任务目录工具入口 | python skills/yt-analysis/scripts/create_workspace.py --help | 通过 |

合计 52 项现有测试通过，另有 2 项 CLI 入口检查通过。命令在新目录执行；依赖安装未运行安装脚本或浏览器下载。

环境：Python 3.14、Node.js 26.8.1。Python 测试使用系统临时目录中的隔离环境，安装 Pillow 12.3.0、OpenAI Python 3.31.0、python-dotenv 1.2.4、Pydantic 2.14.1；Node 依赖使用雷达原 package-lock.json，通过 npm ci --ignore-scripts 安装。Python 禁用字节码写入，content-agent 测试日志通过 CONTENT_AGENT_LOG_DIR 定向至临时目录，未写入历史任务日志。

## 验证边界

content-agent 单元测试对研究模型调用使用 mock；雷达测试检查解析、归并及调度等本地逻辑。YouTube 仅检查 CLI 入口，未验证网络字幕或 Whisper 环境。未调用模型生成内容、采集真实平台数据、生成图片、操作发布页面或执行实际发布。

播放与图片的实际视觉验收、端到端任务完成率、人工修改时间和费用仍按[业务验证方案](../../../projects/01-content-agent/evaluation/README.md)单独开展。
