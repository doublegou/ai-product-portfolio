# StayWord 技术方案

[返回项目](../README.md) · [运行入口](quick-start.md)

![StayWord 双端处理链路与降级分支](../demo/assets/architecture.svg)

## 数据链路与平台选择

输入为麦克风录音或本地音频文件。原文件先进入文件存储；推理读取解码后的 16 kHz 单声道 PCM，VAD 找出语音区间，再用 SenseVoice 生成带起止时间的片段。原音频承担回听，转写承担定位，摘要承担概览。数据库存内容与处理状态，文件系统存音频与模型，避免把所有二进制塞进业务表。

| 层 | iOS | Android |
| --- | --- | --- |
| 界面 / 状态 | SwiftUI / SwiftData | Compose / ViewModel / StateFlow / Room |
| 录音 / 播放 | AVFoundation、MediaPlayer | MediaRecorder、Media3 / ExoPlayer |
| 推理运行时 | Sherpa ONNX；摘要 MLX + Metal | Sherpa ONNX；摘要 ML Kit AICore 或 LiteRT-LM |
| 转写模型 | Silero VAD + SenseVoice | Silero VAD + Pyannote 分段 / 3D-Speaker 声纹 + SenseVoice |
| 系统集成 | Live Activity、WidgetKit、AppIntents | 前台服务通知、MediaSession、WorkManager |

Android 的说话人处理不能推导为 iOS 同样具备。模型与原生库随包发布，需 Git LFS 取回完整文件；缺失权重时，仓库能打开不等于 AI 功能能运行。

## 摘要：模型路由、长文本与降级

### iOS

[SummaryService.swift](../src/stayword-front-ios/StayWord/Services/SummaryService.swift) 使用 `Qwen3.5-0.8B-MLX-4bit`。目标分块长度为 10,000 字符，保持完整转写片段，因此是软目标，单个超长片段不会强行切开。单块直接生成最终摘要；多块逐段总结，再整合为标题和正文。分段输出上限 5,000 token，采样温度 0.2；生成循环设 8 分钟检查期限。该期限在收到流式块时检查，并非独立看门狗，不能保证阻塞时精确超时。

提示词要求只依据输入、保留不确定性，并把输入中的命令作为资料处理。解析器兼容标记结构、纯文本标题和部分不完整标签。格式容错解决可用输出解析，不能证明事实正确，也不能保证抵御所有提示注入。

较旧 GPU 使用更小 prefill 批次：Apple GPU family 8 及以上为 256，否则为 4，减少单次分派压力。代码注释记载 iPhone 12 验证背景，本轮没有重新测量该设备。模拟器明确返回摘要不支持错误，必须用真机验证 MLX。

摘要异常交给协调器：保留转写，记录 `summaryFailureMessage`，整体记录完成；没有自动切到云端或抽取摘要。取消则保留处理状态，以便恢复。

### Android

[SummaryEngine.kt](../src/stayword-front-android/app/src/main/java/com/rivendell/stayword/processing/SummaryEngine.kt) 的真实顺序：

1. 应用在前台且 AICore 状态为 AVAILABLE，尝试系统生成能力。实际系统模型由设备服务决定，应用不是自行分发 Gemini Nano 权重。
2. 不可用、异常或输出与原文归一化后完全一致，尝试随包 Qwen3-0.6B INT4 / LiteRT-LM。
3. LiteRT 先 GPU，失败再 CPU（2 线程）；配置 token 容量 4,096，温度 0.2。文本按 10,000 字符分块并整合。**字符数不等于 token 数**，长中文输入或汇总结果仍可能超出上下文，需要真机边界测试。
4. 仍失败则确定性抽取句子，并标为 EXTRACTIVE。超过 5 句时选首句、约三分之一、三分之二和末句；这保留原句，但不保证选到最重要的信息。

`isDistinct` 只排除归一化后完全相同的文本，不是事实性或摘要质量评估器。`runCatching` 的异常处理也需要补取消传播验证，不能据此宣称所有 OOM 或系统杀进程都已安全恢复。

## 调度与恢复：两端不同的保证

| 情况 | iOS | Android |
| --- | --- | --- |
| 多条任务 | FIFO，一次处理一条 | WorkManager 全局 APPEND_OR_REPLACE 链，串行重型推理 |
| 应用转后台 | 取消当前计算；返回前台继续 | 前台服务通知承载处理；受系统调度与资源限制 |
| ASR 中断 | 每次 emission 保存片段与采样位置 | Worker 恢复重新准备音频和转写；没有同等逐段检查点 |
| 源音频或处理协议变化 | 对比文件大小、修改时间、profileVersion；不匹配则重建片段 | 依当前 Worker 流程重新处理 |
| 摘要失败 | 单独保存摘要错误，保留可用转写 | 尝试抽取摘要；更早的处理失败写 FAILED |
| 删除 / 单条失败 | 当前任务按协调器状态处理 | 删除标记在阶段边界退出；单条失败写业务错误后返回 Worker success，防止后续链被取消 |

Android 的 Worker success 是调度状态，不等于记录处理成功。用户看到的是数据库中的业务状态。来源：[iOS ProcessingCoordinator](../src/stayword-front-ios/StayWord/Services/ProcessingCoordinator.swift)、[Android ProcessingCoordinator](../src/stayword-front-android/app/src/main/java/com/rivendell/stayword/processing/ProcessingCoordinator.kt)。

## 模型与资料完整性

Android 的 [ModelInstaller](../src/stayword-front-android/app/src/main/java/com/rivendell/stayword/processing/ModelInstaller.kt) 依据 manifest 校验大小和 SHA-256，复制到 noBackupFilesDir，防止部分模型被当成成功安装。Android manifest 未声明 INTERNET，备份和设备迁移关闭。系统 AICore 的初始化可用性仍受系统服务条件影响，“应用无网络权限”不能保证所有设备开箱即可使用系统生成。

iOS 音频与处理检查点持久化；摘要加载检查配置和权重是否可读。文件存在检查弱于内容哈希校验，两端模型完整性保证不能混写。原音频仍是核心资产，空间不足、文件丢失与数据库不一致应进入恢复验收。

## 从 VOC 到实现：倍速、三类导出与设置

本轮从原始本地仓库同步 `6eb0369`，而不是在作品集另写一套实现。全部 91 项受版本管理的文件及链接一致；本地源比其 GitHub main 多一个提交。[同步记录](../evaluation/source-sync.json)

- **倍速：**[AudioPlayerController](../src/stayword-front-ios/StayWord/Services/AudioPlayerController.swift) 提供 0.5、0.75、1、1.25、1.5、2×，用 UserDefaults 保存选择，非法保存值回退到 1×。AVPlayer 播放、暂停恢复及 Now Playing 的速率保持一致；系统媒体命令也支持速率变化。
- **导出：**[RecordingExportService](../src/stayword-front-ios/StayWord/Services/RecordingExportService.swift) 从主线程读取不可变资料快照，在独立任务准备临时文件。音频优先硬链接、失败后复制，保留扩展名；转写按时间排序写 TXT，摘要清理标记后写 TXT。无转写、无摘要、缺音频分别报错；成功关闭分享时清理临时目录，下次准备时清理超过 24 小时的遗留目录。24 小时是清理条件，不是后台定时器的保证。
- **设置与识别偏好：**[AppPreferences](../src/stayword-front-ios/StayWord/Services/AppPreferences.swift) 保存普通话、粤语、英语、日语、韩语偏好，经协调器传给 SenseVoice。设置提供评分、联系与版本入口。偏好是识别配置，不等价于每种语言经过同等质量评测。
- **评分时机：**至少 3 天且 3 条不同记录完成后提出评分请求，同版本去重；是否显示由系统决定。这是本地状态机制，不能据此声称有线上活跃统计。

## 已知风险与验证重点

优先验证跨段信息丢失、摘要关键事实错误、长输入 token 溢出、低内存初始化失败、后台恢复重复计算和取消传播。当前源码与历史演示并不构成这些条件全部通过的证据。具体状态与测试卡见[验证记录](../evaluation/README.md)。
