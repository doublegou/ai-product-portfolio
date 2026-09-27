# Social Content Skills

一套项目级的社交媒体内容生产 Skill，目前实现从 YouTube 内容分析到小红书图文创作的完整链路。

```text
YouTube URL
    ↓
yt-analysis → analysis.md
    ├── note-images → plan.md → prompts/ → result/*.png
    └── note-writer → result/post.md
```

## 包含的 Skills

- `yt-analysis`：优先使用 `yt-dlp` 获取人工字幕或自动字幕，生成中文 `analysis.md`；字幕不可用时，经过用户明确同意后才下载音频并使用 Whisper。
- `note-images`：直接读取 `analysis.md`，先生成图片内容规划 `plan.md`；用户确认后生成提示词和小红书系列图片。
- `note-writer`：直接读取 `analysis.md`，独立生成可发布的小红书标题和正文，保存为 `result/post.md`。

`note-images` 和 `note-writer` 互不依赖，可以从同一份 `analysis.md` 并行工作。

## 安装

本仓库需要克隆到工作目录的 `.agents` 文件夹。Codex 打开工作目录后，会从 `.agents/skills` 自动发现这三个项目级 Skill。

### Windows

```powershell
New-Item -ItemType Directory -Force 'D:\posts'
Set-Location 'D:\posts'
git clone https://github.com/seedxdream/social-content-skills.git .agents
```

然后用 Codex 打开 `D:\posts`。

工作目录可以使用其他位置；关键是把仓库克隆为该目录下的 `.agents`。

### macOS / Linux

```bash
mkdir -p ~/posts
cd ~/posts
git clone https://github.com/seedxdream/social-content-skills.git .agents
```

然后用 Codex 打开 `~/posts`。

## 配置 yt-analysis 环境

只有 `yt-analysis` 需要额外的本地运行环境。环境脚本位于这个 Skill 自己的 `scripts/` 目录中。

两个脚本的用途相同，只是适用的操作系统不同：

- `setup.ps1`：PowerShell 脚本，供 Windows 使用；`.ps1` 是 PowerShell 脚本的标准扩展名。
- `setup.sh`：Shell 脚本，供 macOS/Linux 使用；`.sh` 是 Shell 脚本的常见扩展名。
- `setup` 表示“初始化并准备运行环境”。

脚本会创建 Skill 专用的 `.venv`，安装 `yt-dlp`、Whisper 和 PyTorch，准备 FFmpeg 与 Deno，下载 Whisper `base` 模型，并在最后执行自检。

`.venv` 和 Whisper 模型都是本机运行文件，不会上传到 GitHub；换电脑后运行一次对应脚本即可重建。

### Windows

在工作目录中运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\yt-analysis\scripts\setup.ps1
```

Windows 脚本需要可用的 `winget`，并会优先使用系统 Python；找不到时会尝试使用 Codex 附带的 Python。要求 Python 3.10 或更高版本。

### macOS / Linux

在工作目录中运行：

```bash
sh ./.agents/skills/yt-analysis/scripts/setup.sh
```

macOS/Linux 需要 `python3`。脚本在 macOS 上可以通过 Homebrew 安装缺少的 FFmpeg 和 Deno；其他 Linux 发行版需要使用系统包管理器预先安装 FFmpeg。

## 使用方法

### 1. 分析 YouTube 视频

在 Codex 中发送 YouTube 链接，例如：

```text
使用 yt-analysis 分析这个 YouTube 视频：
https://www.youtube.com/watch?v=VIDEO_ID
```

完成后会在当前工作目录创建：

```text
YYYY-MM-DD_HHmm_中文主题/
└── analysis.md
```

`analysis.md` 包含中文概述、带时间戳的完整转译内容和基于完整内容判断的二创方向。

默认先使用 `yt-dlp` 获取字幕，不下载视频。只有字幕不可用时，Codex 才会说明视频信息并询问是否允许使用 Whisper；没有明确同意就不会下载音频。

### 2. 创作小红书正文和图片方案

确认 `analysis.md` 后，可以让两个创作 Skill 同时工作：

```text
使用 note-images 和 note-writer 读取这份 analysis.md，
分别生成图片规划和小红书发布正文。
```

此时会生成：

```text
YYYY-MM-DD_HHmm_中文主题/
├── analysis.md
├── plan.md
└── result/
    └── post.md
```

### 3. 确认图片规划并生成图片

检查并确认 `plan.md` 后，在 Codex 中说明：

```text
确认这个图片方案，继续生成图片。
```

图片提示词和成图会保存为：

```text
YYYY-MM-DD_HHmm_中文主题/
├── prompts/
│   └── NN-type-slug.md
└── result/
    ├── post.md
    └── NN-type-slug.png
```

## 更新

在工作目录中运行：

```powershell
git -C .agents pull
```

普通 Skill 内容更新不需要重新安装环境。只有 `yt-analysis` 的依赖发生变化，或者本机 `.venv` 被删除时，才需要重新运行对应的 `setup.ps1` 或 `setup.sh`。
