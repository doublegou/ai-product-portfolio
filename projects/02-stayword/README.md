# StayWord 端侧语音产品

本项目组保留 iOS、Android 和共享官网的完整工程副本，展示录音、音频导入、转写、摘要与结果管理的产品链路。

作品集重点是：如何在端侧模型质量、设备资源和用户等待体验之间做取舍，并处理长任务的中断与恢复。

## 工程入口

- [iOS 工程](src/stayword-front-ios/README.md)：端侧转写、摘要、录音和系统集成；抽查可见处理队列及中断恢复逻辑。
- [Android 工程](src/stayword-front-android/README.md)：Android 原生实现，具体模型、后台处理和降级路径见原说明。
- [StayWord 官网页面](src/official-landingpage/products/stayword/index.html)：HTML 源码与产品文案。该完整仓库还包括其他产品，不能把它们算成 StayWord 的功能。

两个端分别保持构建配置；模型和原生依赖使用 Git LFS。首次运行遵循各端说明，不将同一模型配置假定为跨端通用。

## 产品案例

- [案例与设计取舍初稿](docs/case-study.md)
- [设备与体验验证方案](evaluation/README.md)
- [演示脚本及素材入口](demo/README.md)

## 开发与阶段

本项目由李适独立完成，涵盖需求、交互、实现与模型选型。此次只整理现有源码和文案，没有验证上架、活跃用户、收入或正式发布状态，也没有完成真机测试。

首版演示优先选择当前最稳定且最能代表核心体验的端，另一端作为补充；不为了作品集强行合并双端工程。
