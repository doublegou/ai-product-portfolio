# Environment

RiverSR 只有这一套项目环境，所有环境相关文件都收在 `env/`：

- `renv.lock`：完整、可复现的 R 依赖清单。
- `library/`：当前电脑实际安装的 R 包，只在本机保存，不提交 Git。
- `activate.R`：项目入口加载环境时调用。
- `bootstrap.R`：新电脑或超算首次恢复环境时运行。
- `packages.R`：项目直接依赖的分类清单。
- `profiles/`：本机与超算的资源配置。

在仓库根目录初始化或恢复：

```powershell
Rscript env/bootstrap.R
```

Base V0 训练节点只需要先恢复建模所需的最小包集合，但仍写入同一套项目库：

```bash
Rscript env/bootstrap.R --v0-only
```

项目脚本会自动调用 `env/activate.R`。不需要根目录 `.Rprofile`，也不依赖 RStudio 工程文件。
