# Bundled model notice

StayWord runs its speech and fallback summarization pipeline entirely on-device. The exact byte sizes,
SHA-256 digests, source locations, and license identifiers for every runtime model are recorded in
`manifest.json`.

- Silero VAD is distributed under the MIT license. Source: `snakers4/silero-vad`; this ONNX export is
  maintained by `k2-fsa/sherpa-onnx`.
- Pyannote segmentation 3.0 is distributed under the MIT license. Its license text is retained in
  `pyannote/LICENSE`.
- The 3D-Speaker ERes2Net model is distributed under Apache License 2.0 by the ModelScope 3D-Speaker
  project.
- SenseVoice model weights and tokens are governed by the upstream FunASR Model License. Attribution
  and the upstream license reference are retained in `sensevoice/LICENSE`.
- Qwen3-0.6B INT4 for LiteRT-LM is distributed under Apache License 2.0, inherited from Qwen3-0.6B.

The Android runtime uses sherpa-onnx 1.13.2, distributed under Apache License 2.0.
