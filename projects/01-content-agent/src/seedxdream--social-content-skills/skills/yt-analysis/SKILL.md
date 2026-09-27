---
name: yt-analysis
description: Analyze a YouTube URL into a Chinese analysis.md for social-media repurposing. Use when the user asks to parse, transcribe, translate, summarize, or adapt a YouTube video. Prefer timestamped manual or automatic captions via project-local yt-dlp; only download audio and use project-local Whisper after explicit approval when captions are unavailable.
---

# YouTube 内容分析

把一个 YouTube URL 转换成唯一的第一层内容资产：

`<posts-root>/YYYY-MM-DD_HHmm_<中文主题>/analysis.md`

开始撰写前，必须完整阅读 [references/analysis-format.md](references/analysis-format.md)。

## 固定执行顺序

1. 在 `posts` 根目录之外创建临时目录，所有字幕、音频和中间 JSON 都放在其中。
2. 使用 `scripts/youtube_transcript.py` 解析 URL。工具会依次尝试人工字幕、自动字幕。
3. 如果字幕不可用，先向用户说明视频标题、时长和预估音频大小；只有得到明确同意后，才可添加 `--allow-whisper` 下载音频并调用 Whisper。
4. 完整读取生成的 transcript JSON，基于整段内容拟定简洁的中文主题。
5. 使用 `scripts/create_workspace.py` 创建任务目录与 `analysis.md` 骨架。
6. 完整填写 `analysis.md` 的三个一级内容部分：`一、概述`、`二、内容`、`三、二创`。
7. 检查 `二、内容` 是否按原始顺序覆盖完整口述内容；每个语义段落以 `[HH:MM:SS]` 开头。
8. 文件核验通过后删除临时目录。此阶段任务目录只保留 `analysis.md`，不要自动开始图片或正文创作。
9. 在 Codex 聊天窗口交付：文件链接、中文完整摘要，以及一个主要二创形式建议（`图文笔记`、`短视频` 或 `长视频`）和简短理由。核心观点与必要背景保留在 `analysis.md` 中，不在聊天窗口重复。

## 二创判断顺序

始终站在全部内容的层面判断，不把“二创”理解成必须另起一个不同选题：

1. 先整理完整内容地图：中心问题、完整结论、主要框架、关键论据、例子、限定条件与行动建议。
2. 优先判断这套完整内容可以直接做成什么方向。如果主题本身已经清楚、有价值并适合目标平台，就保留主题和整体框架，只改写语言与呈现方式。
3. 如果直接使用不够贴合平台，再判断它天然适合轻微改造成什么方向。轻改只调整标题、受众切口、开场、信息顺序、语气或可视化方式，不改变中心命题，也不丢掉主要内容。
4. 只有用户明确要求聚焦某一部分，或者完整内容客观上无法装入目标形式时，才允许截取局部；此时明确说明舍弃了什么以及原因。
5. 在 `三、二创` 中给出一个主要方向，并标明属于“直接改编”还是“轻微改编”，随后写清标题方向、目标读者、核心承诺、完整内容结构和适合的成品形式。

## 命令

在当前项目根目录（即包含 `.agents/` 的目录）下运行：

```powershell
# 拉取字幕；默认不会下载音频
& '.\.agents\skills\yt-analysis\.venv\Scripts\python.exe' `
  '.\.agents\skills\yt-analysis\scripts\youtube_transcript.py' `
  'YOUTUBE_URL' --output-dir 'TEMP_DIRECTORY'

# 得到用户明确同意后才允许 Whisper 回退
& '.\.agents\skills\yt-analysis\.venv\Scripts\python.exe' `
  '.\.agents\skills\yt-analysis\scripts\youtube_transcript.py' `
  'YOUTUBE_URL' --output-dir 'TEMP_DIRECTORY' --allow-whisper

# 创建 YYYY-MM-DD_HHmm_中文主题/analysis.md
& '.\.agents\skills\yt-analysis\.venv\Scripts\python.exe' `
  '.\.agents\skills\yt-analysis\scripts\create_workspace.py' `
  '中文主题' --root '.'
```

在 macOS/Linux 迁移环境中，使用同一 Skill 内的 `.venv/bin/python`，或先运行 `sh scripts/setup.sh` 重建虚拟环境。不要把 Windows 的 `.venv` 直接搬到另一台机器使用。

## 边界

- transcript JSON 只是内部证据，不是交付物。
- 不根据字幕臆测画面；只有用户明确要求并提供可用视频或画面时才做视觉理解。
- `三、二创` 使用独立创作者视角，不出现“原视频”“原作者”“素材中提到”“根据字幕”等来源依附表达。
- `三、二创` 默认基于完整内容提出一个高保真方向。先判断“全部内容可以直接做成什么”，再判断“天然适合轻微改造成什么”；不要为了显得不同而强行换题或只截取其中一小块。标题与结构高度重合并不是问题，原创性主要体现在独立口吻、平台化组织和最终表达。
- 重建环境：Windows 运行 `scripts/setup.ps1`；macOS/Linux 运行 `sh scripts/setup.sh`。
- 自检：运行 `scripts/youtube_transcript.py --self-check`。
