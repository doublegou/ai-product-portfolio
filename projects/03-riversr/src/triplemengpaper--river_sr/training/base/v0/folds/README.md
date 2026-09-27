# Folds

保存 V0 公用且冻结的数据划分：

- `outer_assignments.csv`
- `inner_assignments.csv`
- `fold_diagnostics.csv`
- `fold_manifest.json`

这些文件由 `--stage prepare` 生成一次。正常 smoke/full 只校验其输入数据指纹，不重复生成。
