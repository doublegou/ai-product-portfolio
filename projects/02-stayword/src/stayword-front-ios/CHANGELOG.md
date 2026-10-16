# Changelog

## 1.0.1 (2) - 2026-07-28

### Fixed

- Pin MLX Swift to a Swift 6.2-compatible release so package products resolve
  with Xcode 26.2.
- Keep completed recordings and transcripts available when summary generation
  is unsupported or fails.
- Report the iOS Simulator's bundled-summary limitation without marking the
  recording itself as failed.

### Changed

- Rename the audio action from Upload to Import.
- Remove transcript separators and tighten transcript row spacing.
