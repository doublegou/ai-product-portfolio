# Sherpa ONNX Runtime binaries

`onnxruntime.xcframework` is a version-selecting symlink used by the Xcode
project.

- Active ONNX Runtime: `1.27.0`
- Rollback ONNX Runtime: `1.17.1`
- sherpa-onnx: `1.13.2`
- Execution provider selected by the app: CPU

ONNX Runtime 1.27.0 is repackaged from the official `onnxruntime-c` CocoaPods
artifact:

https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.27.0.zip

Only the static libraries required by this iOS project are retained:

- iOS device: arm64
- iOS Simulator: arm64 and x86_64

The unused native macOS slice and duplicated public headers are omitted. The
runtime binaries themselves are unchanged.
