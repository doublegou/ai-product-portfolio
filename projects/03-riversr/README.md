# RiverSR 建模与科研应用

研究对象为河流水体锶同位素比值。案例重点是从数据、验证设计与失败诊断出发，判断模型能迁移到哪些水系、哪些用途仍不能成立。

本项目组保留建模、早期探索和地图工程，以及本人提供的原始过程笔记。建模结果与地图交互原型分别说明。

## 工程与材料

| 内容 | 入口 |
| --- | --- |
| 当前建模工程 | [river_sr](src/river_sr/README.md) |
| 早期探索工程 | [sr_rf](src/sr_rf/) |
| 地图工程 | [sr_o_map_web_pro](src/sr_o_map_web_pro/) |
| 地图探索版本 | [probabilistic-map-explorer](src/probabilistic-map-explorer/) |
| 原始过程记录 | [模型优化记录final.docx](docs/research-notes/模型优化记录final.docx) |
| 后续研究方案 | [direction2.txt](docs/research-notes/direction2.txt)、[重复原文件](docs/research-notes/direction2(1).txt) |

两份 river_sr 来源提交与文件一致，两份 sr_o_map_web_pro 亦一致，现各共用一个原名目录。全部来源仍记录在 SOURCES.md 和 sources.json；两份原始 TXT 内容一致。

## 案例阅读

- [问题、决策与边界](docs/case-study.md)
- [实验与决策时间线](docs/decision-timeline.md)
- [证据核对方法](evaluation/README.md)
- [演示设计](demo/README.md)

## 当前结论的来源与限制

过程笔记记载：最终选择 RF 作为 5,600 站点全球连续 Sr 回归模型，同时限制高 Sr 水系发现、极高值分类与风险筛查用途。该叙述来自历史记录，本轮没有重训或独立复核全部指标。

Direction 2 为后续研究方案，不能当作已完成实验。所见地图版本包含合成同位素场，热力图颜色未使用查询计算分值；当前只能作为交互原型展示，不能作为已打通真实模型的预测服务。

本项目由李适独立完成。研究数据与其他材料的公开范围仍需单独确定。
