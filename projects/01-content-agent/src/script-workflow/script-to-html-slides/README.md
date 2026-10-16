# script-to-html-slides

把口播脚本制作成有设计感、可离线播放的单文件 HTML 幻灯片的 Codex skill。

页面和页内揭示严格遵循口播顺序；视觉风格随内容选择，套内保持一致。默认交付 `ppt/001.html`、`002.html` 等编号文件，不额外保存原始讲稿或制作过程产物。

## 功能

- 16:9 画布整体缩放，字体、样式、脚本与图形内嵌。
- 点击画面逐步揭示，支持回退、重播、选页和全屏。
- 底部液态玻璃控制栏，鼠标移入显现、移出隐藏，支持键盘操作和减少动态效果。
- 静态资源检查、播放状态测试及浏览器布局审查工具。
- 将内容、技术、视觉分别验收；自动检查不能替代实际逐页审查。

## 安装与使用

将仓库完整克隆到 Codex 的技能目录（目标目录需不存在；已有安装时先检查差异）：

```bash
git clone https://github.com/doublegou/script-to-html-slides.git ~/.codex/skills/script-to-html-slides
```

在 Codex 中调用：

```text
使用 $script-to-html-slides，根据下面的口播脚本制作 HTML 幻灯片。
严格遵循讲述和揭示顺序，生成到当前项目的 ppt 目录。
<粘贴脚本与本次设计要求>
```

完整制作流程见 [SKILL.md](SKILL.md)，已认可的播放器和制作规范见 [production-standard.md](references/production-standard.md)。当前包含个人工作区默认约定；其他项目默认使用其自身的 `ppt/` 目录。黑板手写参考仅为可选风格。

## 目录

- `SKILL.md`：工作流程、约束和验收要求。
- `agents/`：Codex 技能展示配置。
- `assets/`：画布、导航状态、播放器和液态玻璃控件。
- `scripts/`：脚手架、检查工具及回归测试。
- `references/`：设计参考、制作规范和验证记录。

## 开发与检查

工具需要 Python 3；JavaScript 回归测试需要支持 `node:test` 的 Node.js。

```bash
python3 scripts/scaffold.py --output /tmp/slides-draft.html --title '演示标题'
# 编辑生成的 HTML，替换占位页后再执行：
python3 scripts/check_html.py /tmp/slides-draft.html

python3 scripts/test_tools.py
node --test scripts/test_state.cjs scripts/test_audit.cjs
```

生成的 HTML 可直接在浏览器打开，无需安装运行依赖。正式交付前仍需逐页检查内容、字体、布局与实际全屏点击行为。参考图片仅用于说明视觉方向，其内容权利归原作者。
