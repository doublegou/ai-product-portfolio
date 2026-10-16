# 口播脚本转视频配套素材

三个独立 Skill 围绕同一期口播稿协作。这个目录提供整套工作流入口，三个 Skill 保留原项目名、资源、脚本和独立使用能力。

| 阶段 | Skill | 输入 | 交付 |
| --- | --- | --- | --- |
| 演示 | [script-to-html-slides](script-to-html-slides/README.md) | 本期完整口播稿 | 单文件、多页 HTML 演示 |
| 发布文案 | [script-to-post](script-to-post/README.md) | 同一期原稿与发布要求 | 标题、短描述，保存为 post.txt |
| 封面 | [script-to-image](script-to-image/README.md) | 本期 post.txt、原稿、人像参考 | 3:4、4:3、16:9 三张独立构图封面 |

## 执行与交接

整套任务按演示 → 文案 → 封面的顺序执行。演示和文案均直接读取原稿，封面依赖文案的主题和承诺；只需要某一项时可以单独使用对应 Skill。

1. 指定本期脚本和产物工作目录，由 Agent 读取相应 Skill 的 SKILL.md。
2. 用 script-to-html-slides 生成 HTML，保留返回的确切路径。
3. 用 script-to-post 创建本期文案，保留创建工具返回的 post 目录绝对路径。
4. 将该目录、原稿与人像参考交给 script-to-image，不通过最大编号猜本期。
5. 对照同一期原稿检查演示、文案、封面的事实、承诺和范围。

```text
用户指定的产物工作目录/
├── ppt/
│   └── NNN.html
└── post/
    └── MMM/
        ├── post.txt
        ├── 3-4.png
        ├── 4-3.png
        └── 16-9.png
```

NNN 与 MMM 独立编号，不要求相同；图片实际编码为 JPEG／WebP 时使用相应扩展名。正式演示样例可在项目 demo/script-workflow/ 下选择一个任务目录，源码与运行产物分开存放。

## 从作品集使用

在 `projects/01-content-agent/` 下，明确要求 Agent 使用以下本地文件，避免误用其他安装副本：

- `src/script-workflow/script-to-html-slides/SKILL.md`
- `src/script-workflow/script-to-post/SKILL.md`
- `src/script-workflow/script-to-image/SKILL.md`

这三个目录是完整源码，移动目录不要求修改全局 Skill 安装。需要独立安装时使用各工程原有安装说明。

## 本地检查

以下命令从本项目根目录运行，使用合成样例与临时目录，不调用模型或发布内容：

```bash
python3 src/script-workflow/script-to-html-slides/scripts/test_tools.py
node --test src/script-workflow/script-to-html-slides/scripts/test_state.cjs src/script-workflow/script-to-html-slides/scripts/test_audit.cjs
python3 src/script-workflow/script-to-post/scripts/test_post.py
python3 src/script-workflow/script-to-image/scripts/test_check_covers.py
```

封面检查测试需要 Pillow。实际交付还需逐页播放、逐张看图及核对原稿，脚本测试不能代替这些验收。

本流程不包含录音、视频剪辑、平台上传，也不自动调用热点雷达。热点事实按各 Skill 的要求核实；如使用雷达结果，应明确传入本期材料。

## 验收后的版本检查

作品集增加 [check_handoff.py](check_handoff.py)，读取任务 handoff.json 内的确切路径和 SHA-256。它发现验收后输入或成品被修改时返回非零状态，提醒复查关联产物；不替代内容与视觉判断。样例：`python3 src/script-workflow/check_handoff.py demo/script-workflow/2026-10-16-version-alignment/handoff.json`（项目根目录）。该组合工具属于作品集新增实现，不属于三个上游 Skill 的原文件。
