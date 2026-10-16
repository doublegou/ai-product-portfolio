# 出图与定向修订

## 工具与路径

默认走当前内置 `image_gen`，生成前遵循可用 `imagegen` skill。查看真实工具 schema：当前接口主要是 prompt 与参考图机制，不能虚构 `size`、`quality`、`output_path` 参数。比例和像素写进 prompt，再读取实际输出验证。

所有参考都有本地路径时用 `referenced_image_paths`；本地图片先查看。至少一个目标没有路径时，按工具规定用最少数量的最近图片引用；两种机制不混用。不要把最后出现的他人封面误当身份参考。复制或移动工具实际返回的文件，不能猜测生成文件路径。

当前内置工具原图保存在 Codex 管理的输出位置。正式成品复制到明确的本期 `post/NNN/`，命名 `3-4`、`4-3`、`16-9` 并保留正确扩展名；不通过截图工具或 Markdown 缩略图保存低清版。外部 API 只在用户明确选择时使用，并遵守该服务工具的真实限制，不能将研究样例中的接口参数带到本地工具。

## 发布文案衔接

生成前读取本期 `post.txt`。上图标题可以比发布标题更短，但相同核心对象、差异和收益不能改变；不从参考图片继承上一期文字。三个比例的上图文案一致，`post.txt` 本身保持不变。

## 提示词骨架

每个画幅独立展开以下字段；省略不适用项，不把空变量传给出图工具。提示词可暂存系统临时目录以便完整交付，但不存完整口播稿。

```text
Use case: ads-marketing, identity-preserve.
Deliverable: ONE finished Chinese video poster cover, exact <ratio>, target <width>x<height>, full bleed, not a mockup or a collage of multiple covers.
Reference roles: Image 1 = original host identity; Image 2 = approved cover / wardrobe / current series art direction (if present). Other-person style screenshots are described as design language, not identity inputs.
Topic and truthful promise: <what this episode actually covers; no unsupported result or superlative>.
Host: preserve the person in Image 1, facial structure, glasses, hairline, natural age, skin tone and texture. Charcoal short-sleeve crewneck T-shirt with subtle realistic fabric, no added logo. <natural expression and purposeful pose>.
Art direction: <type treatment, palette, light, material, focal hierarchy>; one coherent poster, photographically believable host.
Composition for this ratio: <title block, portrait, content-linked visual, negative space, safe margins>. Do not stretch or crop a different-ratio cover.
Exact visible text, and only this text:
"<brand/topic if needed>"
"<main title>"
"<short subtitle if needed>"
Typography: <precise Chinese type treatment and line breaks>; complete, correct characters; no text over the face.
Supporting visual: <one explanatory object or concise relationship from script; omit unsupported metrics>.
Series invariants: <same wording, same person, same clothing, same palette/type family/topic element>.
Avoid: copied phone UI, player bars, stray slogans, extra people, generic replacement face, facial reshaping, cropped essential text, fake result screenshots, clutter unrelated to topic.
```

不要把所有历史封面的品牌和场景一起传给模型。通常原始人像 + 已通过的主设计即可；必要时补一张准确的产品素材。只有风格参考中完全没有身份混淆时才考虑直接送入，不为了“更多参考”加入整组截图。

## 母版检查与适配

先检查主设计：身份、标题正确、图形逻辑、阅读层级。通过后为其他比例写新的构图段落，保持系列字段不变。主设计是本次内部检查通过，不冒充用户已认可。原始人像始终参与衍生；如其他比例人脸漂移，退回原始人像重做该张，不将漂移传播到全套。

实际输出比例必须读取。`1672×941` 接近但不等于 16:9，不能静默通过。优先用图像工具重新构图/修正，并保留内容；若引擎持续不能给精确尺寸，明确报告能力限制。用户明确授权非生成式裁切/缩放后，可仅校正不会损伤文字和主体的边缘，并复查；不能默认强拉伸或用黑边“凑比例”。

## 单项修订

- 错字：给原图，逐字写出旧词→新词，锁定人像、配色、布局和其他文字；长句反复失败时提议更短等义文案，指定文案不可擅改。
- 人脸漂移：给原图和原始本人照片，要求只修复身份与自然比例，其他内容不变。
- 画面太满：去掉明确的次要元素、扩大标题和脸的读图空间，不盲目加强发光。
- 改比例：明确这是重新排版，锁定身份、衣服、文案和艺术方向，重写所有位置关系。
- 比例合格但文字仍错：仍不通过。尺寸检查不能代替看图。

修订次数按 SKILL.md 限定。先看结果再决定下一步，不能同一错误批量重复。默认不拿代码在错误字上盖色块或叠字；用户明确要求可编辑排版或程序合成时再采用相应流程并如实说明。
