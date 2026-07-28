# StayWord for iOS

StayWord is a private, on-device voice recording and transcription app. It
targets iOS 18 and adopts iOS 26 system appearance and APIs when available.

Record or import audio, keep timestamped transcript segments synchronized with
playback, and generate a concise summary without uploading the recording or
generated content to a server.

## Open and run

1. Open `StayWord.xcodeproj` with Xcode 26.2 or newer.
2. Select the `StayWord` scheme.
3. Choose a development team for the app, test targets, and
   `StayWordRecordingActivity` extension.
4. Run on an iOS 18+ device or simulator.

The app bundle identifier is `com.rivendell.stayword`. The Live Activity
extension uses `com.rivendell.stayword.RecordingActivity`.

## Native system integration

- SwiftUI navigation, lists, forms, search, menus, alerts, sheets, toolbars,
  file importer, ShareLink, Dynamic Type, semantic colors, and SF Symbols
- SwiftData local persistence
- AVFoundation recording and playback with interruption/route handling
- MediaPlayer lock-screen and Control Center playback commands
- Bundled Silero VAD and SenseVoice models for timestamped, segmented,
  on-device transcription
- Bundled MLX/Qwen 0.8B summaries
- ActivityKit and WidgetKit recording Live Activity
- App Intents for starting a recording and opening the latest recording

Only the recording and static audio waveforms are custom drawn. Standard
navigation, controls, materials, dialogs, and transitions are owned by the
system so iOS 26 can apply Liquid Glass automatically.

## Supported audio imports

StayWord publicly supports these mainstream audio formats:

- MP3 (`.mp3`)
- MPEG-4 audio and AAC (`.m4a`, `.aac`)
- Waveform Audio (`.wav`)
- AIFF and AIFC (`.aif`, `.aiff`, `.aifc`)
- Core Audio Format (`.caf`)
- FLAC (`.flac`)

Imported files keep their original container and extension; StayWord does not
rename or recompress them just to fit an internal format. For transcription,
iOS decodes the source locally and StayWord streams it into a normalized 16 kHz
mono PCM representation before voice detection and recognition.

This published list intentionally focuses on formats that are useful to most
people and are supported across import, playback, and processing. iOS can read
additional specialist containers, but those are not part of StayWord's public
compatibility promise.

## Verification commands

```sh
xcodebuild \
  -project StayWord.xcodeproj \
  -scheme StayWord \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project StayWord.xcodeproj \
  -scheme StayWord \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

Microphone recording, on-device model availability, background audio,
interruptions, Live Activity, Dynamic Island, remote media commands, Siri, and
Shortcuts should be validated on a signed physical device.
