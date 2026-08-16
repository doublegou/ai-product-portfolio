# Frozen Regional Risk V1 LOBO design

本目录由`--stage prepare`生成并提交版本管理。`branch_map.csv`必须在不读取response的阶段完成；`label_audit.csv`只做事后审计，不能改变membership。

集群只运行`--stage check`并消费这些已冻结文件，禁止在集群重新prepare。
