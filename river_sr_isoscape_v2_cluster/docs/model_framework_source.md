对，你现在最需要的不是先决定“RF还是XGBoost”，而是把建模问题拆成三层：

1. **什么变量和上游表达方式最合理；**
2. **什么算法最能预测全球主体和极端高值；**
3. **全球统一关系失效时，怎样引入区域／水文地质专家模型。**

你原模型已经完成了很有价值的第一轮探索：4,465个建模点、28个变量、四套空间分块设计；上游地质是空间外推能力第一次明显提升的环节，但最终 spatial CV (R^2) 约0.174、RMSE约0.00955，高值仍存在明显压缩。

我建议把新版设计成下面这套。

# 一、最终架构：全球模型 + 环境专家修正

最终预测不是某一个孤零零的RF，而是：

[
\widehat R_{\text{final}}
=========================

\widehat R_{\text{global}}
+
\sum_{k=1}^{K}
w_k(X)\alpha_k\widehat\Delta_k(X)
]

其中：

* (\widehat R_{\text{global}})：全球主模型；
* (\widehat\Delta_k)：第 (k) 类水文—地质环境中，全球模型残差的预测；
* (w_k(X))：新河段属于该环境的概率或软权重；
* (\alpha_k)：该专家模型在内部空间验证中是否可靠。

这个思路本质上接近 mixture of experts：由一个 gating mechanism 决定不同专家在每个样本上的权重，而不是在地理边界处硬切换模型。([MIT Press Direct][1])

但不要一开始就直接上完整专家系统。需要按顺序证明：

```text
全球统一模型确实系统性失败
        ↓
失败与可解释的水文—地质环境有关
        ↓
区域／环境专家能够在独立空间块中改善预测
        ↓
才进入最终融合
```

# 二、第一步：先重建统一的 predictor table

你原来的变量体系可以保留作为 `P0 baseline`，但新版至少增加三类信息。

## P0：原始28变量

```text
空间坐标
HydroRIVERS水文变量
上游GLiM岩性比例
上游气候与地形
上游黏土
```

这是旧模型基准，不能删，否则无法说明新版到底改善在哪里。

## P1：加强基岩Sr表达

加入Bataille连续型 bedrock Sr，而不是只用分类岩性：

```text
local_bedrock_sr_median
local_bedrock_sr_iqr

up_bedrock_sr_mean
up_bedrock_sr_median
up_bedrock_sr_p75
up_bedrock_sr_p90
up_bedrock_sr_iqr
up_bedrock_sr_sd
up_fraction_sr_above_0.72
```

最后一项不是河水观测值大于0.72的比例，而是：

> 上游流域中，bedrock model预测值高于某个放射成因阈值的面积比例。

这能防止少量极高基岩Sr单元被上游平均值完全抹掉。

同时增加：

```text
local geological age
upstream mean geological age
upstream upper-quantile geological age
lithological diversity
```

## P2：改变上游加权逻辑

同一组上游变量至少生成两个版本。

### 面积加权

[
X_{\text{area}}
===============

\frac{\sum_i A_iX_i}{\sum_i A_i}
]

这是你原来的基准。

### 径流加权

[
X_{\text{runoff}}
=================

\frac{\sum_i A_iQ_iX_i}
{\sum_i A_iQ_i}
]

它避免一大片几乎不产水的上游区域因为面积大，就对下游河水拥有不合理的高权重。

不要把 area-weighted 和 runoff-weighted 的所有变量同时扔入一个巨大模型。先分别建立：

```text
P1A = local + area-weighted upstream
P1Q = local + runoff-weighted upstream
```

单独比较后再决定是否融合。

## P3：补充水文地质过程

建议加入：

```text
channel slope
catchment mean slope
p90 slope
relief
runoff
permeability
porosity
baseflow index
groundwater recharge
glacier fraction
permafrost fraction
lake fraction
dam density
```

直接雪水、冰川水不进入普通河水 response，但冰川、积雪和冻土影响必须保留为流域 predictors。

# 三、先做“变量体系筛选”，再做“算法比赛”

不要一下子把四套 predictors × 五种算法 × 六种区域模型全部跑起来。那会变成一场模型动物园，最后很难解释。

我建议分两轮。

## 第一轮：筛选 predictor architecture

先选两个性质不同的算法：

* Random Forest；
* Cubist/M5 model tree。

对下面四套变量跑相同 spatial folds：

| Predictor版本 | 内容                             |
| ----------- | ------------------------------ |
| P0          | 原始28变量                         |
| P1          | P0 + local/upstream bedrock Sr |
| P2A         | P1 + area-weighted增强变量         |
| P2Q         | P1 + runoff-weighted增强变量       |
| P3          | 最佳上游表达 + hydrogeology          |

之所以保留RF，是因为它是旧模型基准；Cubist/M5类模型则在树划分后的局部区域内使用线性回归，而不是只输出叶节点均值，适合作为“极值是否被常数叶节点压平”的对照。([researchcommons.waikato.ac.nz][2])

这一轮不是选最终算法，而是确定：

> 哪种地质和上游表达方式，在不同算法下都能稳定改善空间预测？

只有跨算法都改善的 predictor enhancement，才值得进入最终模型。

# 四、第二轮：正式比较四类算法

锁定一到两套最好的 predictor architecture 后，再比较：

## 1. Random Forest

作用：

* 保留为benchmark；
* 检验新版变量是否已经足以修复高值；
* 继续提供一个稳定的非线性基线。

RF和QRF仍然有价值，但QRF估计的是训练数据支持范围内的条件分布和条件分位数，并不自动解决稀有高值环境的外推。([Journal of Machine Learning Research][3])

## 2. XGBoost

作用：

* 检验逐步boosting是否比RF更能学习稀有环境；
* 可以使用case weights或自定义损失，专门测试高值误差；
* 处理非线性关系和复杂交互。

XGBoost属于梯度提升树系统，适合大规模表格型数据和加权训练。

## 3. Cubist／M5 model tree

作用：

* 分割不同环境后，在局部环境内拟合连续线性关系；
* 检验bedrock Sr、地质年龄和地形是否存在可以延伸到高值的局部梯度；
* 比纯树叶均值更适合测试“RF尾部压缩”问题。

M5模型树的终端节点使用线性回归模型，而不是简单的常数预测。([researchcommons.waikato.ac.nz][2])

## 4. Local Linear Forest

作用：

* 保留森林对复杂邻域的识别；
* 在森林确定的局部邻域内增加线性修正；
* 专门检验你的响应是否包含强而平滑的地质梯度。

Local Linear Forest就是为标准森林难以拟合强平滑信号的情况提出的。([arXiv][4])

## 暂时不建议进入第一轮的模型

我不会现在就加入：

```text
深度神经网络
普通空间kriging
地理加权回归
几十种AutoML模型
```

你的核心困难不是样本量巨大，而是空间外推、环境异质性和极端值支持。算法数量越多，不代表结论越可靠。

# 五、高值 (R\geq0.72) 应该成为专门的验证任务

你可以用0.72定义一个 **diagnostic tail class**，但不能直接把高值样本抽走、只用它们训练最终模型。

先对0.72做三件事。

## 1. 检查它是不是可靠的独立现象

统计：

```text
独立site数量
独立HydroBASINS数量
独立河流数量
独立reference数量
不同采样年份
不同实验室
青藏高原南部以外的高值样本
```

如果高值主要来自一篇论文或一组相邻样点，问题首先是数据支持度，不是算法。

## 2. 做阈值敏感性

同时检查：

```text
R ≥ 0.718
R ≥ 0.720
R ≥ 0.722
observed top 10%
observed top 5%
```

0.72可以是实际分析阈值，但不能未经检验就当成天然地球化学边界。

## 3. 增加高值专用指标

每个模型都必须报告：

```text
overall RMSE
overall MAE
R²SSE
overall bias

top 10% bias
top 5% bias
RMSE for R ≥ 0.72
bias for R ≥ 0.72
predicted range / observed range
calibration slope
maximum predicted value
```

不能再只凭总体RMSE选择模型。

# 六、模型选择不要只看一个overall RMSE

我建议建立一个明确的选择规则。

## 第一门槛：总体表现

模型必须在四套 spatial shifts 中：

* RMSE和MAE不明显恶化；
* bias保持合理；
* 结果方向稳定。

## 第二门槛：高值表现

至少满足：

* top 5% bias明显减小；
* (R\geq0.72) 的系统低估减小；
* predicted range不再严重收缩；
* 不是靠整体抬高所有预测值来“修复”高值。

## 第三门槛：空间迁移

模型要在：

```text
leave-South-Tibet-basin-out
leave-reference-out
hydrogeological leave-group-out
```

中仍然有效。

空间或层级结构数据使用普通随机CV，会低估真正的预测误差；你的四套空间分块应该继续作为主验证体系。([NSojournals][5])

最终模型不一定是overall RMSE最低的那个，而应该是处在Pareto前沿的模型：

> 总体表现好，同时高值、区域外推和预测范围也不差。

# 七、青藏高原南部可以单独建模，但要分两步

## 第一步：建立“高放射成因环境gate”

训练一个分类器：

[
p_{\mathrm{high}}(X)
====================

P(R\geq0.72\mid X)
]

输入变量只能来自预测时已知的环境：

```text
local bedrock Sr
upstream bedrock Sr p90
high-radiogenic upstream fraction
metamorphic fraction
plutonic fraction
geological age
relief
slope
glacier fraction
runoff
```

这个分类器可以使用：

```text
logistic GAM
XGBoost classifier
RF classifier
```

阈值0.72用于训练label，但全球制图时调用高值专家的依据是 (p_{\mathrm{high}}(X))，不是未知的真实河水Sr。

## 第二步：建立青藏高原／高放射环境残差专家

先用最佳全球模型产生严格的inner spatial OOF residual：

[
e_i
===

R_i-\widehat R_{\mathrm{global},i}^{OOF}
]

再训练：

[
\widehat\Delta_{\mathrm{high}}(X)
=================================

g(e_i\mid X)
]

最终：

[
\widehat R
==========

\widehat R_{\mathrm{global}}
+
p_{\mathrm{high}}(X)
\alpha
\widehat\Delta_{\mathrm{high}}(X)
]

区域专家不应该只使用 (R>0.72) 的样本。应当使用：

* 青藏高原南部或高放射成因环境内的全部样本；
* 高值样本可以给予较高权重；
* 同时保留中等值样本来学习环境边界和过渡。

我建议专家模型优先测试：

```text
Cubist residual expert
GAM residual expert
Local Linear Forest residual expert
```

专家样本量通常有限，不必重新塞入全球全部变量。

# 八、不同地质／水文环境怎么处理？

除了青藏高原高值专家，还需要检查全球是否存在其他稳定环境偏差。

不要预先强行规定“必须六个模型”。先用全球模型的OOF residual诊断：

```text
radiogenic orogenic
carbonate–evaporite
young volcanic
arid–saline
humid deeply weathered
glacial/permafrost
```

只有某一环境满足以下条件，才建立专家模型：

1. 有足够的独立site和流域；
2. 在四套spatial shifts中bias方向一致；
3. 偏差不能由某一篇reference解释；
4. 专家模型在inner spatial OOF中确实改善；
5. 留出完整流域后仍然有效。

最终专家权重应该是soft membership，而不是：

```text
过了某条地质边界，预测突然切换成另一个模型
```

# 九、是否需要最后做算法ensemble？

可以，但放在探索的最后。

假设Cubist高值表现最好，LLF总体RMSE最好，XGBoost在碳酸盐环境最好，那么可以利用inner spatial OOF predictions学习非负stacking weights：

[
\widehat R_{\mathrm{ensemble}}
==============================

\beta_1\widehat R_{\mathrm{Cubist}}
+
\beta_2\widehat R_{\mathrm{LLF}}
+
\beta_3\widehat R_{\mathrm{XGB}}
]

约束：

[
\beta_j\ge0,\qquad \sum_j\beta_j=1
]

权重必须在inner folds中学习，不能根据最终测试结果手动调权。

但假如某一个模型已经在所有关键指标上稳定领先，就没必要为了“高级”强行ensemble。

# 十、concentration放在最后一个结构实验

主模型先比较：

```text
W0：area-weighted upstream
W1：runoff-weighted upstream
```

随后再建立：

```text
W2：predicted concentration × discharge
```

即：

[
F_{\mathrm{Sr},i}
=================

Q_i\widehat C_i
]

[
X_{\mathrm{Sr-flux}}
====================

\frac{\sum_iF_{\mathrm{Sr},i}X_i}
{\sum_iF_{\mathrm{Sr},i}}
]

不把有单位问题的observed concentration直接塞进全球ratio model。

concentration最可能优先改善：

```text
大型汇流河段
碳酸盐流域
蒸发岩和盐化环境
地下水输入明显的环境
```

它未必解决青藏高原高值，因此不应该阻挡当前算法和区域模型探索。

# 十一、完整实验矩阵

我建议控制在下面这个规模。

## 实验A：predictor architecture

```text
A0 旧28变量
A1 + Bataille local/upstream Sr
A2 area-weighted enhanced upstream
A3 runoff-weighted enhanced upstream
A4 + hydrogeology
```

用RF和Cubist做初筛。

## 实验B：算法performance

使用A阶段最好的1–2套predictors：

```text
B1 RF
B2 XGBoost
B3 Cubist
B4 Local Linear Forest
```

## 实验C：高值处理

```text
C0 最佳全球模型
C1 高值case-weighted全球模型
C2 全球模型 + high-radiogenic residual expert
C3 全球模型 + South Tibet geographic expert
C4 全球模型 + geological gate × geographic gate
```

## 实验D：环境非平稳性

```text
D0 global only
D1 global + hydrogeological residual experts
D2 global + hydrogeological experts + South Tibet expert
```

## 实验E：物理加权

```text
E0 area weighting
E1 runoff weighting
E2 Sr-flux weighting
```

这样每个阶段都回答一个独立问题，不会把所有改动混在一起。

# 十二、验证架构

必须使用nested spatial CV。

```text
Outer spatial blocks
    只用于最终模型比较

Inner spatial blocks
    变量筛选
    超参数调优
    算法stacking
    high-value gate
    residual expert
    expert权重alpha
```

此外增加：

```text
leave-reference-out
leave-basin-out
leave-South-Tibet-subregion-out
```

AOA也必须跟最终地图一起输出。AOA用于标识新河段在多维predictor space中是否得到训练样本支持；在AOA之外，空间CV估计的误差不能被直接认为仍然有效。([British Ecological Society Journals][6])

# 十三、为后续水生生物溯源预留的输出

你的最终产品不能只有mean map。

每条HydroRIVERS reach至少需要：

```text
predicted Sr ratio
lower predictive bound
upper predictive bound
AOA / DI
global model prediction
expert correction
high-radiogenic probability
hydrogeological regime weights
nearest training-environment distance
sample support
```

后续水生生物样本应当完全独立，不参与模型选择。河网表达本身非常适合动物来源和食品溯源，因为预测值落在真实river reaches上，而不是无差别覆盖整个陆地。

# 我最推荐的探索路线

先不要决定RF退役，也不要立即把青藏高原样本拆出去。

最合理的顺序是：

```text
更新和整理河水数据
        ↓
统计并核验R ≥ 0.72样本
        ↓
加入Bataille local/upstream高分位信息
        ↓
比较area vs runoff weighting
        ↓
用同一套spatial folds比较RF、XGBoost、Cubist、LLF
        ↓
生成严格OOF residual
        ↓
检验青藏高原和不同水文地质环境的稳定偏差
        ↓
建立high-radiogenic／South Tibet residual expert
        ↓
比较global only与global + experts
        ↓
AOA与不确定性校准
        ↓
concentration sensitivity
        ↓
独立水生生物溯源验证
```

我目前最看好的最终候选不是“一个更复杂的RF”，而是：

[
\boxed{
\text{Cubist或LLF全球模型}
+
\text{runoff-weighted upstream predictors}
+
\text{high-radiogenic residual expert}
+
\text{AOA-aware prediction}
}
]

但这只是**优先检验的假设**，不是预设答案。最后究竟是Cubist、LLF、XGBoost，还是几个模型的空间OOF ensemble，应该由同一套验证体系决定。

[1]: https://direct.mit.edu/neco/article-pdf/6/2/181/812708/neco.1994.6.2.181.pdf?utm_source=chatgpt.com "Hierarchical Mixtures of Experts and the EM Algorithm | Neural Computation | MIT Press"
[2]: https://researchcommons.waikato.ac.nz/entities/publication/d6e1955d-92f8-4993-8999-98be1a1c1b59?utm_source=chatgpt.com "Induction of model trees for predicting continuous classes"
[3]: https://www.jmlr.org/papers/v7/meinshausen06a.html?utm_source=chatgpt.com "Quantile Regression Forests"
[4]: https://arxiv.org/abs/1807.11408?utm_source=chatgpt.com "Local Linear Forests"
[5]: https://nsojournals.onlinelibrary.wiley.com/doi/full/10.1111/ecog.02881?utm_source=chatgpt.com "Ecography - Wiley Online Library"
[6]: https://besjournals.onlinelibrary.wiley.com/doi/10.1111/2041-210X.13650?utm_source=chatgpt.com "Predicting into unknown space? Estimating the area of applicability of spatial prediction models - Meyer - 2021 - Methods in Ecology and Evolution - Wiley Online Library"
