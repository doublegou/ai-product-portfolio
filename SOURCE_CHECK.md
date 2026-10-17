# 来源版本与目录整理核对

核对日期：2026-10-16（Asia/Shanghai）。范围：全部 15 个来源仓库的最新默认分支、导入提交及当前作品集文件。此记录确认版本和文件完整性，不代表应用运行或内容质量验收。

## 2026-10-17 RiverSR 新归档同步

实时查询确认 `triplemengpaper/river_sr` 为 `ad120936a965608ba43794742b18d5caebe68b9d`，`doublegou/river_sr` 仍为 `1cc053e3`。原目录 1,881 个文件中只有 `.gitattributes` 改变，新增上游归档共 7,031 个文件，训练逻辑未变。本轮选入 Base V3 正式运行、最终模型和资源清单等 516 个新增文件，收录范围共 2,397 个文件，逐字节验证通过。

通过上游 Git LFS 下载并校验了 RF 正式模型与 XGBoost 对照快照，RF 发布/运行两个路径共享同一对象。选取的两份模型共 126,805,852 字节，全部与 release 哈希匹配；未将 LFS 指针当成模型文件。历史/smoke 运行和逐折模型保留在上游，未宣称完整目录树一致。[同步清单](projects/03-riversr/evaluation/source-sync.json)

从原始逐折、pooled 与站点均值预测重算主验证和压力测试指标，结果与冻结摘要一致。新增[误差诊断与单站回放](projects/03-riversr/demo/README.md#从逐站结果定位信息缺口)。这次仅恢复归档与复核历史输出，未重训或声明本机 R 推理通过。Natural90 / Human17 / 生物基准后期目录不在该上游提交中。

## 2026-10-17 StayWord 补充同步

原始本地 iOS 仓库的 `main` 已到 `6eb0369c0e3e289054cad81a408cb286ffb8f250`，比 GitHub `main` 的 `70e0c0f` 多一个提交。此前仅核对远端不足以发现这部分更新。本轮已实际同步 17 个文件更新，包括倍速、导出、设置与测试；全部 91 个跟踪条目的文件 SHA-256 和符号链接目标与本地原工程一致。同步后 36 项现有 iOS 单元测试通过。原工程未修改，也未向原仓库推送。

Android `fc0c98b` 与官网 `b0ea849` 已重新查询远端，作品集目录树分别为 `42a0aa3`、`b74d088`，与来源一致。详细结果见 [StayWord 同步记录](projects/02-stayword/evaluation/source-sync.json)。下方表格保留 10 月 16 日的历史核查结果；当前导入版本以 `sources.json` 为准。

## 结论（2026-10-16 历史记录）

以下一致性结论针对当日导入与目录整理时点。其后作品集副本已有明确的执行代码修复，详见末尾“后续产品迭代差异”；当前副本不再宣称与上游逐文件完全一致。

全部来源的默认分支均为 main，远端 HEAD 与导入提交一致；无需拉取新代码。整理前，除一处 CRLF/LF 换行表示外，文件均与来源一致。首次整理后业务代码仍一致，当时有下表记录的三份说明文件修订。随后工作流重构补充的 README 和忽略规则差异见本文末尾，完整清单以 sources.json 为准。

15 个来源记录整理为 13 个原名目录。river_sr 与 sr_o_map_web_pro 的两组重复来源，各自提交与完整目录内容一致后合并；两个来源地址均保留在 sources.json。其他项目仅去掉账号名前缀。原仓库、本机原工程、远端配置和提交历史未修改。

## 逐项结果

| 来源 | 最新 main／导入提交 | 来源文件数 | 整理后的本地差异 |
| --- | --- | ---: | --- |
| [seedxdream/social-content-skills](https://github.com/seedxdream/social-content-skills/tree/3f1522abb67daf29a0757396f9fd83ee9f1b1a67) | `3f1522abb67d` | 68 | 业务代码一致；note-writer 的 README 与 SKILL 目录示意修订，另有 setup.ps1 换行差异 |
| [DualAries-1/content-agent](https://github.com/DualAries-1/content-agent/tree/acd957c8a25ca847e4d934aedb72d943fe17705d) | `acd957c8a25c` | 86 | 业务代码一致；模块与发布说明修订 |
| [doublegou/script-to-html-slides](https://github.com/doublegou/script-to-html-slides/tree/760772ecb1ff1bd370840ba279b4aab08e89d014) | `760772ecb1ff` | 24 | 一致 |
| [doublegou/script-to-post](https://github.com/doublegou/script-to-post/tree/85bc30a0fc67dce4cb242d13ae6106ee6013619c) | `85bc30a0fc67` | 10 | 一致 |
| [doublegou/script-to-image](https://github.com/doublegou/script-to-image/tree/bff70e6a5bb2b27a61f89e7aae12a2cf0af8a006) | `bff70e6a5bb2` | 11 | 一致 |
| [DualAries-1/daily-trend-radar](https://github.com/DualAries-1/daily-trend-radar/tree/eb08b6d5dc3088291434886b2a4e09fc325dcc99) | `eb08b6d5dc30` | 39 | 一致 |
| [DualAries-1/stayword-front-ios](https://github.com/DualAries-1/stayword-front-ios/tree/70e0c0f57074f75985b73f316031f8a10483614b) | `70e0c0f57074` | 88 | 一致 |
| [DualAries-1/stayword-front-android](https://github.com/DualAries-1/stayword-front-android/tree/fc0c98ba1503922475a15a58368b954f2c180c9a) | `fc0c98ba1503` | 74 | 一致 |
| [DualAries-1/official-landingpage](https://github.com/DualAries-1/official-landingpage/tree/b0ea849a6058b14b38485860c3fd7e0cae64a401) | `b0ea849a6058` | 70 | 一致 |
| [doublegou/river_sr](https://github.com/doublegou/river_sr/tree/1cc053e3fc6a410bad83ec99e93c36932b70f188) | `1cc053e3fc6a` | 1881 | 一致 |
| [triplemengpaper/river_sr](https://github.com/triplemengpaper/river_sr/tree/1cc053e3fc6a410bad83ec99e93c36932b70f188) | `1cc053e3fc6a` | 1881 | 一致 |
| [doublegou/sr_rf](https://github.com/doublegou/sr_rf/tree/24715b526acc901ab5c380cbd7d00bef9e9d6d29) | `24715b526acc` | 279 | 一致 |
| [doublegou/sr_o_map_web_pro](https://github.com/doublegou/sr_o_map_web_pro/tree/300ccb1b5b860ddc08f2a1c4ed9850f911f28aa7) | `300ccb1b5b86` | 19 | 一致 |
| [triplemengpaper/sr_o_map_web_pro](https://github.com/triplemengpaper/sr_o_map_web_pro/tree/300ccb1b5b860ddc08f2a1c4ed9850f911f28aa7) | `300ccb1b5b86` | 19 | 一致 |
| [doublegou/probabilistic-map-explorer](https://github.com/doublegou/probabilistic-map-explorer/tree/85788f9c9d28ab3564201f48234976cc0b91a676) | `85788f9c9d28` | 69 | 一致 |

## 核对方法与边界

- 通过 GitHub API 读取每个仓库的 default_branch、提交 SHA 和 tree SHA，与 sources.json 基线比较；没有以本地旧 remote 引用代替实时远端查询。
- 从来源提交的 Git tree 逐项取文件清单与 blob，计算当前文件 Git blob 哈希；符号链接按链接目标文本校验。
- Git LFS 文件按来源指针中的 SHA-256 与字节数校验实际展开内容：iOS 8 个、Android 6 个，全部通过。
- social-content-skills 的 setup.ps1 本地使用 CRLF，来源 blob 使用 LF；规范化换行后内容完全一致，该差异整理前已存在，没有修改脚本逻辑。
- 两组重复目录在合并前额外逐文件比较（包括目录中的非跟踪文件），内容一致；没有删除独有文件。
- 整理后再次核对全部来源，只出现登记的三份说明修订与上述换行差异；源码目录没有额外文件。
- 此结论是核对时的默认分支快照，不包含所有历史分支，也不意味着未来原仓库更新会自动同步。

## 作品集本地修订

1. social-content-skills/skills/note-writer/README.md：对齐当前只读 analysis.md、只写 result/post.md 的职责，原始说明可在来源提交查看。
2. social-content-skills/skills/note-writer/SKILL.md：将 prompts/ 的目录示意改到任务根目录，与 note-images 契约一致。
3. content-agent/docs/content_strategy_loop.md：补充已有 publish 模块、默认发布行为和只生成草稿的开关说明。

以上路径相对各自源码根目录；sources.json 的 portfolio_changes 同步登记。未更改生成、采集、模型、发布或训练执行逻辑。本次不进行实际发布、真机推理或科研重训。

## 整理后检查

- 23 份作品集及本轮修订文档中的 86 个本地链接全部有效。
- 源码符号链接无失效项。
- 13 个源码目录的 2,718 个来源文件均已按新路径纳入 Git 变更，包括原本被嵌套忽略规则覆盖的历史日志和数据。
- git diff --check 通过；本轮仅整理目录和文档，未执行应用功能测试。

## 后续内容生产项目重构

同日，第一个项目进一步从平铺 src/ 迁入 workflows/ 与 tools/。上面的来源版本核对结论仍有效；在三份说明修订之外，social-content-skills 和 content-agent 的 README 增加了作品集使用路径，content-agent 的 .gitignore 补充了本地 .venv/。新增 script-workflow/README.md 属于组合入口，不属于任一原工程。六个工程迁移前后的文件校验和离线测试见[重构验证记录](projects/01-content-agent/evaluation/refactor-check.md)。

## 最终结构落地（2026-10-16）

上述 workflows/、tools/ 迁移为历史阶段。当前第一个项目代码已归回 src/，YouTube 板块命名为 content-workflow；其他板块为 script-workflow、content-agent、daily-trend-radar。来源地址与提交保持不变，六项 path 和相关文档已更新。迁移前后 239 个文件（含组合入口）已核对；本轮仅四份 README 因名称／路径调整变化，业务执行文件未变。新的离线测试与校验记录见[结构验证记录](projects/01-content-agent/evaluation/structure-check.md)。此步骤未重新查询远端，远端版本结论沿用本文同日核对快照。

## 后续产品迭代差异（2026-10-16）

目录整理完成后，为修复真实任务暴露的问题，仅在作品集副本增加以下差异：

- content-agent/run_daily.py：保存成功即计入已保存结果，避免发布异常抹掉该状态；新增 tests/test_daily_persistence.py。
- daily-trend-radar/scripts/run.mjs：全源失败仍保存诊断报告，再以非零状态结束；新增 test/cli-failure.test.mjs，README 补充运行与邮件边界。
- script-workflow/check_handoff.py 与 test_handoff.py：作品集组合层新增的版本交接检查，不属于三个上游 Skill 的源码。

前两项已登记在 sources.json 的 portfolio_changes，三个 script Skill 仍保留导入版本。本节不声称重新查询过远端；最新查询时点仍为本文首次核对。当前验证见[投递材料审查](projects/01-content-agent/evaluation/release-review.md)。原仓库与原本地工程未修改。


## 审改一致性修订（2026-10-16）

在作品集副本中修正 content-agent/src/create/runtime.py 的事实 guard 改稿提示，避免引导产品稿插入生成工具的实现说明；memory/account/acceptance_standards.md 去掉与实际门槛重复的 8.2 项，保留 8.6。新增 tests/test_review_runtime.py 四项离线回归，内容 Agent 15 项测试全部通过。变更已登记 sources.json，未同步到原仓库。未新增模型生成、发布或远端版本查询；历史评分与原稿保持原样。
