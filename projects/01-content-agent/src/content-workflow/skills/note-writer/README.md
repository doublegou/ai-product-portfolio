# note-writer

从当前任务的 `analysis.md` 生成小红书标题与正文，唯一输出为 `result/post.md`。这是 [content-workflow](../../README.md) 中的正文分支，与 note-images 共同读取分析文件。

## 工作关系

```text
analysis.md
  ├─ note-writer → result/post.md
  └─ note-images → plan.md → prompts/ → result/系列图片
```

note-writer 不搜索外部资料、不规划或生成图片、不依赖或修改 plan.md。需要完整图文时分别调用两个分支；正文完成不代表图片规划已确认。

## 使用与交付

指定本期 analysis.md 或其任务目录，按 [SKILL.md](SKILL.md) 执行。它会读取创作者声线与去机械感规则，选择角度、写作并核对素材事实。

post.md 第一行是唯一最终标题，之后留三行空白再写正文；默认不加话题标签，不另存候选标题、评分、图片说明或中间长稿。修改时更新本期文件。

## 资料与来源

本目录保留了借鉴资料、历史示例和许可；其中较宽泛的搜索、图文、视频制作说明不能替代当前 SKILL.md 的输入输出契约。历史演示图片不是本作品集本轮的运行结果。

作品集本地修订仅对齐说明与现行 Skill，未改生成逻辑。[导入版本的原 README](https://github.com/seedxdream/social-content-skills/blob/3f1522abb67daf29a0757396f9fd83ee9f1b1a67/skills/note-writer/README.md) 保留于来源提交与 Git 历史中。
