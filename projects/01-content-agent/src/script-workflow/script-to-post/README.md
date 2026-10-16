# script-to-post

根据口播脚本生成视频发布标题和正文的 Codex skill。标题表达核心主题与具体观看收益；正文默认 2～3 句、80～150 字。

## 安装

将完整仓库放到 `~/.codex/skills/script-to-post/`。目标目录不存在时可运行：

```bash
git clone https://github.com/doublegou/script-to-post.git ~/.codex/skills/script-to-post
```

已有安装时先检查本地修改，再更新。

## 使用

```text
用 $script-to-post，根据以下本期脚本生成标题和正文，保存到 post 的下一个编号目录。
```

规则和操作步骤见 [SKILL.md](SKILL.md)。创建脚本从 `004` 开始递增，不补空号、不覆盖旧内容；修改已有期使用原目录。`post.txt` 只保存唯一的最终标题和正文。

## 工作流

1. [script-to-html-slides](https://github.com/doublegou/script-to-html-slides) 生成 HTML 幻灯片，仍保存到项目的 `ppt/`，独立编号。
2. 本 skill 创建 `post/NNN/` 并写入 `post.txt`。
3. [script-to-image](https://github.com/doublegou/script-to-image) 读取该目录文案，生成 `3-4.png`、`4-3.png`、`16-9.png`，保存在同一目录。

图像实际编码为 JPEG/WebP 时使用对应扩展名。制作发布素材不包含上传社交平台。

## 工具

需要 Python 3，仅使用标准库。

```bash
python3 scripts/create_post.py --post-root /path/to/post --title-file /tmp/title.txt --description-file /tmp/description.txt
python3 scripts/check_post.py /path/to/post/004/post.txt
python3 scripts/test_post.py
```

创建时可用 `--dry-run` 预览而不占编号。检查工具报告结构、字数及需复核措辞，不能代替对照脚本核查事实与文案质量。维护源码位于项目 `post/script-to-post/` 时，应同步对应安装副本。
