# Sherpa ONNX Runtime binaries

The Xcode project uses these version-selecting symlinks:

- `sherpa-onnx.xcframework` → sherpa-onnx `1.13.4`
- `onnxruntime.xcframework` → ONNX Runtime `1.27.1`

No older runtime fallback is retained. The app uses the CPU execution provider.

The static libraries are repackaged without modifying their binary contents
from these official release artifacts:

- https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.4/sherpa-onnx-v1.13.4-ios-no-tts.xcframework.zip
- https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.27.1/onnxruntime-ios-static-xcframework-1.27.1.zip

Only the architectures required by this iOS project are retained:

- iOS device: arm64
- iOS Simulator: arm64 and x86_64

Duplicated public headers and unused platform slices are omitted.
