# Regional expert projects

`regional_risk_v2/`已完成喜马拉雅区域风险Gate的顺向2×2实验：固定比较probability RF与shallow boosting，以及Full50与Full50 + Process14。17-fold strict Nested LOBO的68/68个Outer任务全部完成；四个候选均未满足完整Gate，最终状态冻结为`NO_CANDIDATE_MET_COMPLETE_REGIONAL_GATE`，未拟合full-data model，未创建release。

`regional_failure_audit/`是其下游只读失败审计：固定分析Full64背景重叠、跨branch最近邻和Process14 failure case，不训练模型、不修改threshold或Gate。审计支持结构性信息缺口结论，并将后续工作限定为引入新区域/机制信息的Regional Expert，而不是继续调优同一套64维predictors。

该审计现已完成并通过超算复算，是区域专家模型路线的最终收尾。对`probability_rf__full50`完全漏检的8个positive branches（28个high-Sr stations），Full64变量落在普通背景5%–95%区间内的站点中位比例为95.3%，没有变量同时具备强单变量区分能力与低背景重叠；排除同branch后的Full64 5-NN中，high-Sr邻居比例为6.4%，低于全域21.5%。Process14的背景区间重叠中位数为100%，同样没有满足联合判据的变量。

最终结论：GAM、RF和XGBoost的共同失败主要是information problem，而不是algorithm-selection problem。当前64维predictor space无法充分编码部分high-Sr水系的形成机制。该路线到此冻结，不再围绕相同predictors继续调参；未来若重启，必须引入新的区域、branch、地质、水文地球化学或process-specific信息。
