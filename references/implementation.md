# HTML 接口

`scripts/scaffold.py` 将 `assets/base.css`、`assets/state.js`、`assets/player.js` 和 `assets/liquid-controls.*` 内嵌到一个 HTML。液态玻璃控制栏是本用户工作流默认；正文舞台不限定黑板风格。生成出的初始页面是未完成占位页，静态检查会拒绝它；编辑替换后才能交付。制作标准与样板见 [production-standard.md](production-standard.md)。

## 舞台和分步

```html
<main class="deck-stage">
  <section class="slide" id="slide-1">
    <h1 data-qa-block="heading">标题</h1>
    <div data-step="1" data-qa-block="diagram">主要图解</div>
    <p data-step="2" data-qa-block="conclusion">结论</p>
  </section>
</main>
```

- `.slide` 是 `.deck-stage` 的直接子节点。无 `data-step` 的元素进页即显示；`data-step="0"` 亦可。
- 正整数 step 按不同数值排序推进；相同数字同时出现，允许 1、3、8 这样的非连续编号。
- 不要把较早出现的元素嵌在较晚显示的父元素里。嵌套分步时子节点编号应不小于父节点，最终仍需看中间状态。
- `?slide=2&step=1&clean=1` 定位第二页的第一组揭示、隐藏控件；不是秒数。参数会限制到有效范围。
- `.deck-stage` 的 `data-page`、`data-step`、`data-steps` 是只读检查用状态。不要在成品上显示内部调试信息。
- 控件、键盘和触摸都使用同一状态转换；连续点击直接进入确定节点，过渡可中断，不积压旧动画回调。`R` 回到本页初始状态，左退跨页时进入上一页完整状态。
- `Space/Right` 下一步，`Left` 上一步，`PageUp/PageDown` 翻页，`R` 重播，`V` 纯画面，`Esc` 恢复，`F` 全屏，`?` 帮助。文本输入时不截获快捷键。
- `--stage-width/height` 决定设计坐标；`--bg/fg/accent`、字体、字号、间距和揭示过渡均可按套设计。基础 sans-serif 只是可运行回退，不是最终字体选择。
- 自动播放、定制形变、线条绘制属于扩展功能；增加后检查手动回退和重播是否恢复它们，不只恢复播放器计数。

## 检查标记

- `data-qa-block="简短名称"` 标记独立主要内容区，审查器会检查块之间的重叠。不强制卡片布局。
- `data-qa-text` 可标记普通选择器未覆盖的主要文本。
- `data-qa-overlap` 仅用于设计上有意叠放的块；不要用它消除真实遮挡报告。`data-qa-bleed` 允许指定图像/图形有意出血，正文不可借此隐藏越界。
- 先推进到要检查的状态，等待字体和过渡完成，在浏览器的只读 evaluate 中执行 `scripts/audit-layout.js` 的整个表达式。读取文件内容并作为字符串传入即可；不要为了审查去改页面状态或禁用 CSS。
- 审查器是启发式几何检测，不完整理解 SVG 路径、字体轮廓、遮罩、阴影和意图；`review` 项要结合截图。空报告不是视觉质量或所有状态通过的证据。
- 自定义旧 HTML 没有此接口时可适配检查选择器，但不要据此错误报告它没有页面；不要为通过检查而无谓重写。
