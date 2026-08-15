# Environment

RiverSR 使用项目级 `renv` 环境。本目录保存依赖清单、首次启动脚本和本机/超算运行配置。

## 初始化

在仓库根目录运行：

```powershell
Rscript environment/bootstrap.R
```

脚本会安装 `renv`，安装 `packages.R` 中声明的依赖，并在仓库根目录生成或恢复 `renv.lock`。

当前本机环境已经完成：R 4.6.1 已安装并加入用户 PATH，直接依赖与完整依赖树已经写入根目录 `renv.lock`。超算使用同一个 lockfile 恢复环境。

`profiles/local.yml` 和 `profiles/hpc.yml` 只控制资源与路径来源，不改变统计方法、随机种子或模型配置。
