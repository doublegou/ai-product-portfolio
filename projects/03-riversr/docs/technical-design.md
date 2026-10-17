# RiverSR 数据与技术方案

[返回项目](../README.md) · [研究案例](case-study.md) · [研究规划](decision-timeline.md)

## 数据如何形成

我把观测清洗、空间关联、特征提取和模型训练拆成独立阶段，使每次数据扩充都能定位变化来源。模型训练读取正式数据版本，历史参考目录不参与运行。

| 阶段 | 实际处理 | 质量控制与取舍 |
| --- | --- | --- |
| 基础站点 | 6,283 条原始观测聚合为 4,527 个候选站点；4,485 个满足初版 Full50 准入 | 观测记录与训练站点分开，保存站点身份与聚合响应 |
| 九来源补充 | 1,950 条记录保留来源号、DOI/URL、许可证、坐标、日期和 QC 字段 | 10 条可能与旧版重复的记录保留在观测层，但排除训练准入 |
| 候选合并 | 1,940 条准入记录按五位小数坐标形成 1,122 个新增候选；与基础候选合为 5,649 站 | 原 4,485 站点的 ID 和响应不变 |
| 河网与流域 | 分配 HydroBASINS L6，构建上游闭包；在 HydroRIVERS 上按 5 km 规则匹配 | 最终保留 5,600 站，新增 1,115；匹配约束是空间关联规则，不等于定位误差为零 |
| 环境表示 | 提取局地/上游岩性、地质年龄、水文、气候、土壤和地形 | 空间尺度和单位进入特征定义；不能用局地点值静默替换上游统计 |
| 版本交付 | 写出 Full50、分层计数、来源统计及 SHA-256 manifest | 正式 V2 构建以恢复的历史 Full50 快照对齐特征，保留正向构建的 ID、来源与水文元数据 |

最后一步保留历史快照，是为了恢复与正式实验一致的输入，而非宣称每个历史特征都能仅凭当前脚本从零重建。旧 4,485 站在 V2 中曾重新提取特征，因此校验的是旧站身份/响应一致，以及 V2 特征与 V2 快照一致；不要求 V2 特征逐格等于 V1。

[原始数据下载清单](../src/river_sr/data/raw/features/download_inventory.csv)保存了 36 项资源的来源 URL、字节数和 SHA-256，原清单状态均为 verified，总计约 3.84 GB。仓库保留清单与构建代码，完整地理原始数据按清单取得。

来源：[补充观测管线](../src/river_sr/data_pipeline/observation/sr_supplement_v1/README.md)、[Full50 V2 构建](../src/river_sr/data_pipeline/training/sr_full50_v2/README.md)、[数据 manifest](../src/river_sr/data/processed/training/sr_full50_v2_manifest.json)。

## 特征如何表达研究问题

| 输入信息 | Full50 中的表示示例 | 在研究中的作用 |
| --- | --- | --- |
| 地理位置 | 三维球面坐标编码 | 提供空间背景；需要检验其他信息是否超越位置代理 |
| 水文与河网 | 流量、上游/局地汇水面积、河段长度、上下游距离、河流级别 | 表达站点所处河网位置与汇水尺度 |
| 地质 | GLiM 局地/上游岩性比例；地质年龄均值、离散程度、古老地质比例 | 表达潜在源区与局地背景的差异 |
| 气候 | WorldClim 温度、降水及季节性；Global-AI_ET0 干旱度和蒸散 | 提供气候环境背景 |
| 地形与土壤 | 高程；SoilGrids 表层 clay 与 pH，含局地/上游汇总 | 补充地表与流域环境特征 |

这 50 个变量属于早期基线。后续 Natural90 / Human17 已扩展输入，但不能写成这份 Full50 模型已经使用了这些信息。区域 Process14 则是现有变量上的过程衍生表示，需通过 Full50 / Full64 对照证明增量价值。[完整变量清单](../src/river_sr/training/base/v3/release/full50_predictors.txt)

## 输入、特征与冻结契约

Base V3 输入为 `sr_full50_v2.csv`：5,600 站点，响应变量 `sr87_sr86`，冻结 Full50 预测变量。水文系统来自 HydroBASINS level-6 的 MAIN_BAS，正式设计记载 364 个系统，其中 13 个含 Sr ≥ 0.75，5 个含 Sr ≥ 0.80。站点、水系和特征清单先冻结，再训练。

文本输入按 LF 规范化后计算 SHA-256，二进制按原始字节计算；跨平台换行不会改变输入身份。64 位流域编号通过 bit64 保持精度。数据派生预处理只在当前训练分区拟合，不能用外层测试数据计算填充值等统计量。

来源：[科学设计](../src/river_sr/training/base/v3/SCIENTIFIC_DESIGN.md)、[实现决策](../src/river_sr/training/base/v3/IMPLEMENTATION_DECISIONS.md)、[50 特征清单](../src/river_sr/training/base/v3/release/full50_predictors.txt)。

## 验证场景与泄漏控制

| 环节 | 可能导致乐观偏差的路径 | 采用的隔离方式 |
| --- | --- | --- |
| 站点分组 | 同一水系的上下游同时进入训练和测试 | Base V3 内外层均按完整 MAIN_BAS 分组 |
| 支流验证 | 留出支流，却保留携带其上游信息的下游站点 | Base V2 外层及内层执行 downstream purge；branch 定义不使用 Sr 响应 |
| 数据预处理 | 用全数据中位数等统计量填充训练数据 | 每个训练分区独立拟合，再应用到对应 assessment |
| 模型选择 | 看完测试结果再选权重、参数或分类阈值 | 内层完成选择，外层只评价；已结束实验的失败诊断不重新打开选择 |
| 二层修正 | 使用训练内拟合的 Base 预测作为修正层输入 | 在相应训练分区内部重新 cross-fit Base 预测 |
| 结果汇总 | 把三次预测视为三个独立站点，或用大支流掩盖小支流 | 区分 pooled 与站点均值；同时报告站点和水文单元表现 |

Base V2 的匹配基准比较验证几何，Base V3 的固定分组比较模型；两类实验改变的因素不同。空间压力测试与来源分组用于诊断其他迁移条件，不能与主任务混合排名。

## 严格嵌套验证

外层 3 repeats × 5 folds，同一完整水系不跨训练与测试；每个外层训练集再建 5-fold 水系隔离内层。每站有 3 次严格 OOF 预测。

内层选择结构与权重，外层只评价冻结候选。RF 池有 378 种结构，XGBoost 有 1,728 种；每个外层任务用相同 48 粗筛 + 16 细化结构预算，各结构比较 W0 / W1 / W2。W2 在四个 Sr 区间的权重为 1 / 2 / 4 / 8；**验收指标不加权**，不能通过给高值更大权重来掩盖实际误差。

内层先以 RMSE 确定 0.5% 范围内候选，再以尾部识别、低值误报、偏差等打破近似并列。算法最终选择用 pooled strict Outer-OOF RMSE，MAE 与绝对偏差作确定性平局规则。两个层次的规则不同，不要混写。

## 模型训练与冻结配方

这里以源码与冻结产物齐全的 **Full50 / Base V3** 展开训练实现；Natural90 / Human17 使用不同特征、人群与模型任务，后续部分单独列出，不套用这份 RF 配方。

训练单位是一个 `model × repeat × outer fold`。流程依次完成：验证输入/分组哈希 → 读取训练分区 → 内层搜索 → 冻结候选 → 外层一次评价 → 保存 OOF、模型与预处理统计。RF 使用 `ranger` 回归，XGBoost 使用平方误差目标与 `hist` 树构建；线程数读取 `SLURM_CPUS_PER_TASK`，没有配置 GPU 训练。

| 训练阶段 | RF | XGBoost | 计算与验证含义 |
| --- | --- | --- | --- |
| 粗筛 | 48 结构 × 3 权重 × 5 内折，500 树 | 相同候选/权重/折预算；最多 3,000 轮，50 轮 patience | 先覆盖参数空间，权重与结构一起选 |
| 细化 | 16 结构 × 3 权重 × 5 内折，1,000 树 | 相同细化预算；仍以内层 early stopping 选轮数 | 在有希望的结构附近继续比较 |
| 外层评价 | 选定结构，2,000 树 | 使用内层选中轮数的中位数，外层不 early-stop | 外层标签不参与参数或轮数选择 |
| 部署选参 | 汇总 Primary 结构证据，最多 16 结构重新 grouped tuning | 同样在 Primary 支持的 shortlist 上选择 | 确定单一配方；调参分数不作为新泛化成绩 |
| 压力与最终拟合 | stress 2,000 树，最终 4,000 树 | 冻结轮数用于 stress 和最终拟合 | 压力测试后不重新追分，最终拟合用于交付与容量诊断 |

单个外层任务的内层 fit 数为 `(48 + 16) × 3 × 5 = 960`，再加 1 次外层拟合。30 个任务的 **Primary 配置预算为 28,830 次 fit 调用**。这是基于配置的计算规模，不是读取完整运行账单得到的实执行次数；部署、stress、最终拟合、smoke 和重试另外计入。[训练脚本](../src/river_sr/training/base/v3/scripts/02_primary_task.R) · [训练函数](../src/river_sr/training/base/v3/R/common.R) · [配置](../src/river_sr/training/base/v3/config/base_v3.yml)

| 项目 | RF | XGBoost |
| --- | --- | --- |
| 冻结结构 | rf_110 | xgb_1535 |
| 主要参数 | mtry 12；min node 1；无放回；sample fraction 0.8 | depth 8；eta 0.05；child weight 5；subsample / colsample 1；lambda 1；alpha 0.1；gamma 0 |
| 权重 / 最终规模 | W2；4,000 树 | W1；118 轮 |
| 轮数控制 | 冻结树数 | 内层最多 3,000 轮，50 轮 patience；冻结内层选中轮数的中位数用于外层拟合 |

算法选定后另做全数据 grouped tuning，选择部署配方。这个分数不是无偏泛化估计。固定配方再做 500 / 1,000 / 1,500 km 空间分块与 reference 分组压力测试，不允许根据 stress 结果再调参。

这些空间压力测试是 EPSG:6933 正方形分块，不能描述成“每个测试站点周围清空相应公里数”的距离缓冲实验。后者属于 Direction 2 提出的另一类设计。

## 训练资源、耗时与成本

### 资源申请与运行规模

| Base V3 阶段 | 任务数 | 每任务 CPU / 内存申请 | 每任务时限 |
| --- | ---: | --- | --- |
| RF Primary | 15 | 16 CPU / 32 GiB | 36 h |
| XGBoost Primary | 15 | 16 CPU / 32 GiB | 48 h |
| Deployment | 2 | 16 CPU / 32 GiB | 36 h |
| RF + XGBoost stress | 40 | 16 CPU / 24 GiB | 8 h |
| 检查、聚合、最终拟合、结果检查 | 4 | 默认提交器统一 8 CPU；内存按阶段 12–32 GiB | 分别 1 / 2 / 12 / 2 h |

表中是 `run.sh` 与 sbatch 的默认请求，命令行可覆盖。默认 Primary 并发为每算法 5 任务，共 160 CPU；stress 每算法 10 任务，共 320 CPU。正式 RESULTS 记录的申请峰值更高：Primary 480 CPU、stress 640 CPU；这些是该次运行的资源规模记录，不能拿默认配置替代，也不代表实际 CPU 利用率。控制任务以提交器的覆盖值为准，不能只读取 sbatch 中的 `cpus-per-task`。

[Slurm 提交器](../src/river_sr/hpc/slurm/base_v3/run.sh) · [任务配置目录](../src/river_sr/hpc/slurm/base_v3/) · [正式运行结果](../src/river_sr/training/base/v3/RESULTS.md)

### 从保留日志能测出什么

我重新解析了仓库内 **119 份 run.log**，将每个任务最后一组完整开始/结束记录与 `task_info.json` 对齐。V1 日志含早期追加运行，汇总时排除旧记录，不能把重复日志算成新增任务。时间戳精度为 1 秒。

| 日志范围 | 任务 / 模型拟合 | 日志中的应用计时 | 如何解释 |
| --- | --- | --- | --- |
| Regional V1 最后一轮 | 85 任务 / 85 次模型拟合 | 09:03:07–09:03:12；任务时长合计 55 s | 多任务并发；单任务 0–1 s，受日志精度限制 |
| Regional V1.1 | 34 任务 / 578 次 GAM 拟合，另有 34 校准器 | 09:13:25–09:13:39；任务时长合计 271 s | Environment 单任务中位 5 s，Combined 中位 11 s |
| Base V3 | 已收录 76 作业单元对应的 152 份 stdout/stderr、任务产物与作业 ID | 日志包含候选完成与阶段完成信息，缺少完整任务起止和 sacct | 能追溯执行内容，仍不能计算总训练耗时或实际核时 |

以上应用时间均来自 2026-08-17 的任务日志；不包含排队、R/包加载前的耗时和其他流程阶段。尤其不能把 V1.1 的 14 秒窗口写成“整个项目训练只用 14 秒”，也不能把并发任务的 271 秒加总当作用户等待时间。[可重复提取脚本](../evaluation/summarize_training.py) · [逐任务记录及哈希](../evaluation/training-evidence.json)

### 成本怎样核算

我将计算成本拆成**有效实验、失败恢复、数据处理与存储**。当前材料可以确定任务结构、申请配置和部分应用计时；实际费用取决于完整调度账单与集群单价；科研配额同样纳入资源预算。

若集群按分配 CPU 核时计费，核算为：`Σ(AllocCPUS × ElapsedRaw / 3600) × 核时单价`，再加平台适用的内存、存储或其他费用。应逐个任务统计，父 array 汇总与子任务、batch step 不能重复累加。`CPUTimeRAW` 是分配 CPU 时间，`TotalCPU` 是使用的 CPU 时间，两者可用于检查利用情况；实际结算仍以平台规则为准。[Slurm sacct 字段定义](https://slurm.schedmd.com/sacct.html)

项目需要保留的计量字段包括 run_id、任务/attempt、分配 CPU、ElapsedRaw、TotalCPU、MaxRSS、状态和退出码；没有实际运行时间与单价时，只能做配置预算，不能提供实际费用。后续归档恢复可直接补入同一口径，不改变已经冻结的科学指标。

## 失败恢复、资源取舍与交付

正式依赖顺序为：检查 → 两算法 Primary → 聚合 → 部署选参 → 固定配方 stress → 最终拟合 → 结果检查。`afterok` 使下游阶段依赖上游成功；各阶段显式指定 run_id，参数、输入、分组与源码哈希共同标识运行。

| 工程选择 | 节约或保护了什么 | 实际边界 |
| --- | --- | --- |
| 500 → 1,000 → 2,000 → 4,000 树逐级增加 | 在候选筛选阶段控制 RF 计算量 | 不能将不同树数的 fit 次数直接换算为等量 CPU 成本 |
| XGBoost 内层早停 | 不为每个候选都跑满 3,000 轮 | 外层不使用测试标签 early-stop |
| 完成一个候选的五个内折后原子保存摘要 | 同 run_id 重提时跳过已完成候选 | 当前未完成候选需重新跑；不是每棵树或每轮 boosting 都能恢复 |
| 轻量可行性 → 校准/阈值 → 更强模型 | 先回答是否存在信号，再决定是否扩大计算 | 研究门槛在看到外层结果前固定 |
| 结果与工程状态分开 | 避免输出/校验失败使有效计算全部重跑 | 结果内容仍须完整、版本与哈希一致 |

Base V3 正式运行 76 个作业单元完成；Regional V2 最终完成 68 个任务、1,156 次拟合。Regional V2 前两次因计算节点 `libstdc++` 加载顺序在工程检查阶段停止，修复依赖后完成正式运行，没有为环境错误重设科学方案。后续 Human17 重分析的 55 个输出失败任务只恢复对应索引，未重跑有效任务；这是后续执行回报中的恢复记录，不计入 Base V3 成本。[区域工程与结果](../src/river_sr/training/regional_expert/regional_risk_v2/RESULTS.md) · [后续恢复记录](../evaluation/later-research-records.md#执行与恢复)

研究交付包括配方、特征定义、预处理统计、分组、验证结果、科学结论和模型快照。Base V3 保留 RF release bundle 与 RF / XGBoost 最终运行快照，通过 LFS 管理并按发布哈希校验。RF bundle 为 126,650,268 字节，对照 XGBoost 为 155,584 字节；体积差异不用于推断精度或推理速度。后续 Natural90 / Human17 模型尚未随执行回报归档。[Base V3 release](../src/river_sr/training/base/v3/release/README.md)

## 后续 Natural90 / Human17 的实验合同

| 项目 | 后续设计与执行回报 |
| --- | --- |
| 数据人群 | canonical 5,600；Natural90 主研究 5,543；Human17 配对 5,517 |
| 模型任务 | M1 为自然基线；M2/M3 在完全相同配对人群比较自然变量与加入人类活动变量 |
| 比较范围 | RF / XGBoost / LightGBM；空间 500 / 1,000 / 1,500 km、reference、水文迁移 |
| 科学约束 | 测试身份、folds、水文 purge、候选、种子和 gate 冻结；H13 修复仅改变应改变的输入 |
| 配对不确定性 | 每个单元 2,000 次 bootstrap，报告误差差值与区间，区分实质改善、实际等价与不确定 |
| 重分析规模 | 210 Outer contexts、25,920 candidate-fold checkpoints；不能直接与 Base V3 的配置 fit 次数相加 |
| 保护性验证 | Natural90 主模型/全球图不变；未受影响的 Human14 与 Sensitivity7 字节不变 |

该部分的精确参数、二进制与调度耗时需以后续冻结工件为准。本页不把早期 Full50 的 `rf_110 / W2`、16 CPU 默认申请或空间分块定义迁移到新实验。[后续回报与完整配对表](../evaluation/later-research-records.md)

## 如何解释两种 OOF 汇总

- pooled：5,600 × 3 = 16,800 条预测，用于本次算法比较。不是 16,800 个独立站点。
- site mean：每站 3 次预测先平均，再在 5,600 站点上评价，便于站点与区间诊断。
- training：全量拟合后回看训练数据，只用于容量诊断。

三次重复共享站点，不能直接视为独立同分布样本来构造置信区间。[逐站重算脚本](../evaluation/reproduce_predictions.py)读取 33,600 行两算法 Primary 预测与 44,800 行压力测试预测，核对原始逐折输出、测试身份、每站三次预测均值，并重算 RMSE、MAE、Bias、R² 和极高值命中，与冻结摘要一致。该过程未重新训练模型。

RF 的 136 个实测 ≥0.75 站点占 2.43%，贡献 82.90% 的站点均值平方误差。此分层基于实测响应，是失败分析；不能在未知站点直接用该分层选择模型，也不构成机制或因果证明。[误差诊断与单站回放](../demo/README.md#从逐站结果定位信息缺口)

## 地图原型的真实依赖

[isotope.ts](../src/sr_o_map_web_pro/src/domain/isotope.ts) 的 `fieldAt` 生成确定性合成值，查询网格按各输入密度计算与归一化。这个 score 是原型中的相对分值，不是经校准的真实地理来源概率。

[ProbabilityMap.tsx](../src/sr_o_map_web_pro/src/components/ProbabilityMap.tsx) 使用 `displayProbabilityAt(coordinate)` 绘制颜色，尚未直接绑定网格 `cell.score`。因此查询模块单测通过，也不能推出视觉输出正确响应查询。真正接入前应先修复绑定关系、增加输入改变→颜色改变的端到端验收，再接真实栅格、模型版本和不确定性。
