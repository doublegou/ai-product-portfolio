# Quick Start：从已有材料开始

[返回项目首页](../README.md)。以下命令均从仓库根目录开始；四个模块独立选择，不必全部安装。新产物放在 `runs/` 或明确指定的工作目录，保留历史案例原件。

## 1. 不调用模型：检查现有任务交接

需要 Python 3。运行：

```bash
python3 projects/01-content-agent/src/script-workflow/check_handoff.py \
  projects/01-content-agent/demo/script-workflow/2026-10-16-version-alignment/handoff.json
```

预期六个文件均匹配，退出码为 0。若出现 missing 或 changed，应核对输入与产物，不能仅更新哈希让检查变绿。该检查只识别验收后的文件变化，不判断内容对齐。

## 2. content-workflow：从分析到正文与卡片

需要能读取本地 Skill、执行字幕工具并生成图片的 Agent 环境。使用本仓库的三个文件，避免混用其他安装版本：

- [yt-analysis](../src/content-workflow/skills/yt-analysis/SKILL.md)
- [note-writer](../src/content-workflow/skills/note-writer/SKILL.md)
- [note-images](../src/content-workflow/skills/note-images/SKILL.md)

在项目根目录 `projects/01-content-agent/` 打开 Agent，先发送：

```text
读取 src/content-workflow/skills/yt-analysis/SKILL.md，
分析这个视频：[替换成视频链接]。
产物写入 runs/video-trial/，保留来源与时间戳。
```

查看分析后，再指定这份 `analysis.md`，按 `note-writer` 和 `note-images` 生成正文与图片规划；说明读者、张数和风格。规划确认后生成图片。字幕工具的首次环境配置见[源码说明](../src/content-workflow/README.md#配置-yt-analysis-环境)；字幕缺失时，按 Skill 的转写确认流程处理。

**无字幕时的处理。** 工具返回 `whisper_confirmation_required`（退出码 3）时，先查看标题、时长及音频大小估计；许可下载和本地转写后，才增加 `--allow-whisper`。从仓库根目录的调用形式为：

```bash
projects/01-content-agent/src/content-workflow/skills/yt-analysis/.venv/bin/python \
  projects/01-content-agent/src/content-workflow/skills/yt-analysis/scripts/youtube_transcript.py \
  'YOUTUBE_URL' --output-dir 'TEMP_DIRECTORY' --allow-whisper
```

将两个占位符换为实际视频链接与临时目录。未许可时不加该参数；已有字幕仍使用字幕。下载／解析失败和指定语言缺失不是自动转写触发条件。首次安装需准备 Whisper base 模型，转写使用 CPU；[技术说明](architecture.md#4-字幕获取与-whisper-降级)列出资源清理与结果字段。

**验收出口：** 打开 `analysis.md`、`plan.md`、`result/post.md` 和成图，核查来源、图片独立阅读、数量和实际尺寸。可对照[文献综述案例](../demo/content-workflow/2026-08-27-literature-review/README.md)。

## 3. script-workflow：只生成本期需要的素材

需要支持本地文件与相应生成能力的 Agent；生成封面还需要图片生成能力和人像参考。在项目根目录提供完整口播稿及已有素材，用以下模板明确范围：

```text
本期原稿：[替换成实际文件路径]。
读取 src/script-workflow/script-to-post/SKILL.md 生成发布文案，
再读取 src/script-workflow/script-to-image/SKILL.md，
依据本期 post.txt、原稿与我提供的人像参考制作三比例封面。
已有录制画面，本次不需要演示。产物工作目录：runs/script-trial/。
返回本次创建的确切目录，不按最大编号推测。
```

需要演示时使用 [script-to-html-slides](../src/script-workflow/script-to-html-slides/SKILL.md)，打开产出的 HTML 逐步播放。GitHub 文件页展示 HTML 源码，播放需下载到本地浏览器；这份 HTML 是视频配套产物。

**验收出口：** 检查稿件与文案的主题和承诺，再检查三张封面文字与比例。PPT 与 post 编号可不同，使用[交接检查说明](../src/script-workflow/README.md#验收后的版本检查)记录本期真实文件。已有素材与新产物可以组合交付。

## 4. content-agent：生成候选稿

需要 Python 环境及兼容 OpenAI 接口的模型服务。以下为最小草稿路径，跳过平台研究与发布：

```bash
cd projects/01-content-agent/src/content-agent
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

首次使用参照 `.env.example` 新建 `.env`，设置 `OPENAI_API_KEY`、`OPENAI_BASE_URL` 和 `MODEL`；已有配置直接检查。产品资料在 `memory/products/`，账号和平台约束见[配置说明](../src/content-agent/README.md)。确认实际产品事实后执行：

```bash
python run_once.py "给 BirdTracker 写一篇面向观鸟新手的介绍，聚焦图鉴、热点线索和观察记录" \
  --no-research --no-publish
```

**验收出口：** 通过程序内部审稿后输出 `saved_path`，草稿在 `data/drafts/`，运行记录在 `data/logs/`。达到审改上限仍未通过则失败退出，查看原因；取得草稿后逐项核对产品主张。`approved` 代表内部规则通过。

本命令会消耗模型额度。源码默认入口包含发布行为，示例中的 `--no-publish` 明确限定为草稿；`--publish-dry-run` 仍会操作发布页，不能替代此参数。需要平台研究时另按源码配置浏览器与采集条件。

## 5. daily-trend-radar：采集一份报告

需要 Node.js 20+、npm 和可访问来源的网络：

```bash
cd projects/01-content-agent/src/daily-trend-radar
npm ci
mkdir -p ../../runs/radar-trial
node scripts/run.mjs --sources github,hackernews,v2ex --limit 5 --format json \
  --output ../../runs/radar-trial/report.json
```

**验收出口：** 查看 `sourceStatus` 与 `items`；每源五条是请求上限，不保证取得数量。失败先检查具体来源诊断；在已配置代理的环境中按 Node 版本的代理支持设置运行环境，不需要修改系统网络设置。若三源均可用，预期最多 15 条。

将报告与受众方向交给 Agent，要求回查原文并将事实、内容角度、待验证项分开，可参考[选题简报](../demo/daily-trend-radar/2026-10-16-source-check/brief.md)。命令只采集并保存报告，不会发邮件或启动下游创作。

## 6. 复跑本轮产品评测

在已装好 content-agent 依赖的 Python 环境，从仓库根目录执行：

```bash
python projects/01-content-agent/evaluation/2026-10-17-product-audit/audit.py
```

脚本读历史日志、图片和构造样本，执行当前事实规则，更新同目录 `results.json`。无需模型密钥，不重新采集或发布。预期规则探针为 6/12 符合期望；这份评测保留当前缺陷，不以全绿为目的。完整口径见[评测说明](../evaluation/2026-10-17-product-audit/README.md)。
