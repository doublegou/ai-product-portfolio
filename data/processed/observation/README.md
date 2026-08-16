# Processed observation releases

本目录保存观测数据项目生成的正式、可审计观测 release。训练数据管线只读这里的成果，不直接解析 `reference/`。

- `sr_supplement_v1.csv`：九来源 1,950 条补充河流/溪流水观测；其中 1,940 条通过跨版本重复筛选，可进入 Full50 V2 候选站点构建。
- `sr_supplement_v1_manifest.json`：输入与输出 SHA256、来源计数、Sr 分层和训练准入计数。
