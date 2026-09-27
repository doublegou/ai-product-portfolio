# Global correction projects

依次复现 `global_high_sr_risk` 和 `high_sr_correction_feasibility`。修正实验必须使用严格的 OOF Base 预测，禁止读取同一行的拟合内预测。

`high_sr_correction_feasibility` 已冻结为 strict nested Oracle 设计：15 个 repeated grouped Outer tasks 内各规划 5 个 single-exclusion、10 个 canonical pair-exclusion 和 1 个 full-Outer Base fit。它独立于 `global_high_sr_risk` 的输出，只共享冻结训练表与 Base V1 folds。
