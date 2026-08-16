# Regional expert projects

`regional_risk_v2/`是喜马拉雅区域风险Gate的顺向2×2实验：固定比较probability RF与shallow boosting，以及Full50与Full50 + Process14。它使用17-fold strict Nested LOBO和inner-only FPR10 threshold，共68个Outer任务。本地阶段只冻结与检查工程，正式训练由独立HPC工作流接管，结果回收后才落实Gate结论。
