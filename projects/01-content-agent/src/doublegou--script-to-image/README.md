# script-to-image

根据本期脚本和发布文案，制作 3:4、4:3、16:9 三张同主题、分别构图的海报封面的 Codex skill。

## 安装

将完整仓库放到 `~/.codex/skills/script-to-image/`。目标目录不存在时可运行：

```bash
git clone https://github.com/doublegou/script-to-image.git ~/.codex/skills/script-to-image
```

已有安装时先检查本地修改，再更新。

## 使用

```text
用 $script-to-image，读取 post/004/post.txt，结合本期脚本和我的人像参考生成三张封面，保存在同一目录。
```

规则见 [SKILL.md](SKILL.md)。默认使用 Codex 内置图像生成能力和当前 `imagegen` 规范；三种画幅独立构图，并检查中文、人像、实际比例与可读性。个人默认包括炭灰短袖，可被本次要求覆盖；配色与设计随选题选择。

## 工作流与交付

先由 [script-to-post](https://github.com/doublegou/script-to-post) 创建文案并返回本期确切目录；本 skill 沿用该目录，不重新分配编号。

```text
post/004/
  post.txt
  3-4.png
  4-3.png
  16-9.png
```

如果实际编码为 JPEG/WebP，使用对应扩展名。PPT 仍按 [script-to-html-slides](https://github.com/doublegou/script-to-html-slides) 的原规则保存在 `ppt/`，不与发布素材编号绑定。

## 人像参考

本机的本人照片和风格参考位于 `assets/private/`，该目录不上传 GitHub。克隆仓库后，使用本次提供的人像和风格图片，或自行将参考放入该本地目录；具体角色与优先级见 [设计约定](references/design.md)。缺少参考时不凭空生成“本人”。

## 检查

检查工具需要 Python 3 和 Pillow；优先使用工作区已有依赖，或在独立虚拟环境安装 Pillow。

```bash
python3 scripts/check_covers.py /path/to/post/004
python3 scripts/test_check_covers.py
```

工具只读检查四个文件、图片编码、尺寸比例与分辨率，不验证审美、人像或文字准确性。还需实际看图复核；不保证点击率。维护源码位于项目 `post/script-to-image/` 时，应同步对应安装副本。
