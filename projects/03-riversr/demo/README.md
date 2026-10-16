# RiverSR 实际产物

[返回项目](../README.md)

## 研究结果：比较与用途限制

![正式模型证据](assets/model-evidence.png)

图表直接读取 Base V3 冻结 CSV，由 [render_figures.py](render_figures.py) 生成。RF 的严格 OOF 误差优于 XGBoost，但两者均未命中 29 个极高值站点。训练集高命中与陌生水系漏检同时展示，避免只选有利结果。

完整产物还包括：[50 个预测变量](../src/river_sr/training/base/v3/release/full50_predictors.txt)、[RF 冻结配方](../src/river_sr/training/base/v3/release/rf_recipe.json)、[预处理统计](../src/river_sr/training/base/v3/release/training_medians.csv)、[严格验证摘要](../src/river_sr/training/base/v3/validation/README.md)、[科学结论](../src/river_sr/training/base/v3/release/scientific_conclusion.md)与[版本及二进制哈希](../src/river_sr/training/base/v3/release/final_manifest.json)。模型二进制未随 Git 附带，不能仅凭克隆此作品集直接推理。

## 地图：运行已有工程得到的界面

**以下是合成数据交互原型，不是真实模型预测，也不是地理来源结论。**

![本轮运行的 RiverSR 地图交互原型，合成数据](assets/map-prototype.png)

2026-10-17 本轮在现有 `sr_o_map_web_pro` 工程运行 Vite 后，由 Chromium 捕获，视口 1440 × 1000；示例在 Strontium central 50% 输入 0.7100 后点击 Run，其余输入为空；没有重绘界面或补造模型结果。底图来源按界面 attribution 保留。

使用过程为：在 Sample Query 选择同位素输入 → 点击 Run → 查看地图、修改条件重跑。误差使用域模块默认配置，界面目前没有独立误差输入。表单有计算状态与重置处理，域模块提供合成值和网格分值；但渲染色彩目前使用独立展示函数，未直接消费查询 score。它说明了原型形态，同时暴露了端到端接口缺口。

这项缺口应先于真实预测接入修复；修复后再用固定输入检查颜色、数值、图例和范围是否一致。现有单测通过不能代替这一验收。当前没有把科研模型输出伪装成已上线的地图服务。

## 后续值得补的证据

真正有价值的是真实栅格与模型接入后的同一查询全链路：输入与模型版本 → 预测数值和不确定性 → 地图响应 → 不支持区域的提示。Direction 2 的结果图必须等实验完成后生成；目前仅保留方案，不制作模拟成绩截图。
