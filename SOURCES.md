# 来源与导入说明

三个项目组的源码按原项目名存放，不附加账号前缀。15 个来源记录对应 13 个源码目录；同提交、同内容的重复来源共用一份目录。导入默认分支时使用不压缩历史的子目录合并，原始提交作者、时间和 SHA 可在历史中追溯。新的组合提交和仓库创建时间是本次产生的，不伪装成旧项目时间。

当前不提供所有分支和标签的完整镜像承诺；仅推送作品集 main。已取回的额外本地来源引用不作为作品集功能分支发布。

所有源码目录在导入时通过 Git tree 对比核对，详见 sources.json。后续如果修改副本，应保留此来源版本作为基线。

| 项目组 | 来源 | 提交 | 本地副本 |
| --- | --- | --- | --- |
| 01-content-agent | [seedxdream/social-content-skills](https://github.com/seedxdream/social-content-skills) | `3f1522abb67d` | [目录](projects/01-content-agent/src/content-workflow/) |
| 01-content-agent | [DualAries-1/content-agent](https://github.com/DualAries-1/content-agent) | `acd957c8a25c` | [目录](projects/01-content-agent/src/content-agent/) |
| 01-content-agent | [doublegou/script-to-html-slides](https://github.com/doublegou/script-to-html-slides) | `760772ecb1ff` | [目录](projects/01-content-agent/src/script-workflow/script-to-html-slides/) |
| 01-content-agent | [doublegou/script-to-post](https://github.com/doublegou/script-to-post) | `85bc30a0fc67` | [目录](projects/01-content-agent/src/script-workflow/script-to-post/) |
| 01-content-agent | [doublegou/script-to-image](https://github.com/doublegou/script-to-image) | `bff70e6a5bb2` | [目录](projects/01-content-agent/src/script-workflow/script-to-image/) |
| 01-content-agent | [DualAries-1/daily-trend-radar](https://github.com/DualAries-1/daily-trend-radar) | `eb08b6d5dc30` | [目录](projects/01-content-agent/src/daily-trend-radar/) |
| 02-stayword | [DualAries-1/stayword-front-ios](https://github.com/DualAries-1/stayword-front-ios) | `70e0c0f57074` | [目录](projects/02-stayword/src/stayword-front-ios/) |
| 02-stayword | [DualAries-1/stayword-front-android](https://github.com/DualAries-1/stayword-front-android) | `fc0c98ba1503` | [目录](projects/02-stayword/src/stayword-front-android/) |
| 02-stayword | [DualAries-1/official-landingpage](https://github.com/DualAries-1/official-landingpage) | `b0ea849a6058` | [目录](projects/02-stayword/src/official-landingpage/) |
| 03-riversr | [doublegou/river_sr](https://github.com/doublegou/river_sr) | `1cc053e3fc6a` | [目录](projects/03-riversr/src/river_sr/) |
| 03-riversr | [triplemengpaper/river_sr](https://github.com/triplemengpaper/river_sr) | `1cc053e3fc6a` | [目录](projects/03-riversr/src/river_sr/) |
| 03-riversr | [doublegou/sr_rf](https://github.com/doublegou/sr_rf) | `24715b526acc` | [目录](projects/03-riversr/src/sr_rf/) |
| 03-riversr | [doublegou/sr_o_map_web_pro](https://github.com/doublegou/sr_o_map_web_pro) | `300ccb1b5b86` | [目录](projects/03-riversr/src/sr_o_map_web_pro/) |
| 03-riversr | [triplemengpaper/sr_o_map_web_pro](https://github.com/triplemengpaper/sr_o_map_web_pro) | `300ccb1b5b86` | [目录](projects/03-riversr/src/sr_o_map_web_pro/) |
| 03-riversr | [doublegou/probabilistic-map-explorer](https://github.com/doublegou/probabilistic-map-explorer) | `85788f9c9d28` | [目录](projects/03-riversr/src/probabilistic-map-explorer/) |

## 重复与共享内容

- doublegou/river_sr 与 triplemengpaper/river_sr 的最新默认分支、导入提交及本地文件一致，共用 `projects/03-riversr/src/river_sr/`。
- 两份 sr_o_map_web_pro 同样经过核对，共用 `projects/03-riversr/src/sr_o_map_web_pro/`。
- official-landingpage 为多个产品共享官网，完整保留，StayWord 案例只使用其中对应部分。
- 三份研究笔记置于 SR 项目内，两个 TXT 相同；哈希记录在 sources.json。

## 独立维护

唯一作品集推送目标是 doublegou/ai-product-portfolio。仅在这个新本地仓库内，来源 remote 的推送地址被设为 DISABLED，以避免误推；该设置不影响其他目录的原项目和远端链接。源仓库的自动化配置随原工程保留在子目录，不迁到作品集根目录执行。

## 大文件与当前状态

StayWord 模型及原生依赖继续使用 Git LFS；传输完整性见 IMPORT_CHECK.md。源码实现与附件保留，少量作品集文档修订单独记录；这并不意味着已经核准公开所有历史、数据或配置。保持私有期间先做案例整理，公开前另行确认。

## 2026-10-16 核对与本地修订

全部 15 个来源默认分支均与导入提交一致，无需同步新代码。逐文件与 LFS 校验、范围及差异见 [SOURCE_CHECK.md](SOURCE_CHECK.md)。命名整理不修改原项目、远端或提交历史。

本地修订包括 social-content-skills 的 note-writer README 与 SKILL 目录示意、content-agent 的模块和发布说明、两者的本地运行 README，以及 content-agent 的 .venv/ 忽略规则。此处记录目录整理阶段；后续已修复 content-agent 的保存计数与 daily-trend-radar 的失败报告，并新增 script-workflow 交接检查，详见 [SOURCE_CHECK.md](SOURCE_CHECK.md#后续产品迭代差异2026-10-16)。原始来源版本继续保留，具体文件列于 sources.json 的 portfolio_changes，后续同步需保留这些修订。

## 内容生产项目目录重构

第一个项目统一使用 docs、demo、evaluation、src。源码按 content-workflow、script-workflow、content-agent、daily-trend-radar 四个板块组织；script 三个原工程一起放在 src/script-workflow/，另有组合入口 README。content-workflow 是约定的展示与目录名称，原 social-content-skills 仓库地址保留用于追溯。六个来源内部结构保留，sources.json 的 path 指向当前根目录；本地 README 引用同步更新；目录迁移本身未改业务逻辑，后续功能修复单独记录。
