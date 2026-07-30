# Bundled summary model

- Model: `mlx-community/Qwen3.5-0.8B-MLX-4bit`
- Source revision: `5d894f8cc4ef3e6c88537bf3746ed262f549da6a`
- Runtime: MLX Swift LM `ee026ba` (`3.31.4` + Qwen3.5 compiled decode and GDN decode FMA)
- MLX Swift: `0.31.6`
- Quantization: affine 4-bit, group size 64
- License: Apache-2.0, inherited from `Qwen/Qwen3.5-0.8B`
- `model.safetensors` SHA-256:
  `f5a0d9dd3efa73510542a8023d610ff26be2b4b020d181cfc4bedaa1fcc5dd9e`

The model is bundled under `Models/Summary/Qwen3.5-0.8B-MLX-4bit` so summary
generation does not require network access. Audio, transcripts, prompts, and
generated summaries remain on the device.
