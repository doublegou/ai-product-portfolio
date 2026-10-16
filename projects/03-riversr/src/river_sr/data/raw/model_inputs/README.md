# Recovered model inputs

本目录保存旧工程遗失后仍可恢复、但不能由现存中间成果逐值再生的冻结模型输入。它们是正式、带哈希的数据资产，不是临时 `reference/` 材料。

- `full50_v1_predictors.csv`：4,527 站、99 列；其中 4,485 站通过历史 complete-P0 规则。SHA256 `109d1ac32b31682986c2ad52f3766194ea63df3e7f551d57065bf749c62657ce`。
- `full50_v2_5600_snapshot.csv`：Base V3 对应的 5,600 站、67 列模型输入快照，含 50 个 Full50 predictors。SHA256 `386f4f795a38a11e4b238c0e460b1c883a08c42b1ed88bf2ad6823866e4cb6b0`。

V1 与 V2 是两个独立特征版本。V2 在历史上重新抽取过旧 4,485 站的 predictor，因此二者不得互相覆盖，也不得用“V2 保持 V1 predictor 不变”作为验收条件。
