# StayWord · Quick start

[返回项目](../README.md)

## 先体验一条任务

可从 [App Store](https://apps.apple.com/app/id6795797415) 查看已发行 iOS 版本；商店版本不等同于本仓库工程快照。无需安装也可看[实机视频](../demo/assets/stayword-demo-2026-09-25.mp4)。

1. 使用一段自己的、无敏感信息的 30–90 秒音频，包含一个日期、一个数字和一项行动；在“所有录音”的菜单导入，或现场录制。
2. 等待语音检测、转写和摘要状态推进。先确认原音频已保存并可以播放。
3. 在转写页检查日期、数字与否定词；播放对应段落核对，不仅检查有没有文本。
4. 切换摘要，检查行动归属和约定时间；保存、收藏或使用当前版本提供的分享入口。
5. 记录设备、系统、版本、音频时长、处理时间及发现的错误。当前版本未提供某个历史演示入口时，以实际界面为准。

预期拿到原音频、带时间戳转写以及摘要或独立的摘要失败信息。没有摘要时，先检查转写是否仍可用，避免把整条记录当成丢失。

## 运行 iOS 工程

需要 macOS、Xcode（工程说明要求 26.2+）与 iOS 18+；完整模型测试需要真机。以下从作品集仓库根目录执行：

```bash
git lfs pull
cd projects/02-stayword/src/stayword-front-ios
open StayWord.xcodeproj
xcodebuild -project StayWord.xcodeproj -scheme StayWord \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:StayWordTests CODE_SIGNING_ALLOWED=NO test
```

模拟器名称以 `xcrun simctl list devices available` 为准。Xcode 中为应用与扩展设置自己的签名 Team，再选择真机运行。模拟器不能验证 MLX 摘要，显示不支持提示属于实现边界。第一次构建需要下载 Swift Package 依赖及 Xcode Metal Toolchain；Git LFS 失败则先修复模型和原生库，不能用占位指针构建。本轮 Xcode 27.0 / iOS 26.5 模拟器已通过 29 项单元测试。若出现 `_mlx_*` 未定义符号，检查临时 Swift Package checkout 的 `mlx-c` 子模块是否完整，再按锁定提交取回；不要先改模型代码。

## 运行 Android 工程

需要 JDK 17、Android SDK 36.1、API 31+ 设备；模型为大文件。不要在没有取回模型时把构建成功当作完整验证。

```bash
git lfs pull
cd projects/02-stayword/src/stayword-front-android
./gradlew verifyModelAssets lintDebug testDebugUnitTest assembleDebug
```

用 Android Studio 配置 SDK 与设备后安装 Debug APK。系统生成能力取决于设备 AICore；不可用时应走随包模型或抽取摘要。真机录音、后台通知、蓝牙与模型内存表现需单独测量。详细依赖和权限见 [Android 工程说明](../src/stayword-front-android/README.md)。
