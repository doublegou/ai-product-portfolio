# Base V3 frozen release

Source run: `base_v3_full_20260817_r2`

Selected model: Random Forest `rf_110 / W2`

This is the approved Base V3 global continuous-Sr regression release. It is not
approved for high-Sr system discovery, extreme-value classification or risk
screening; strict hydrological-system-isolated OOF recall at `Sr >= 0.80` is
0/29 sites and 0/5 systems.

Compact validation summaries, recipes, preprocessing medians, frozen inputs
and provenance are tracked here. `model_bundle.rds` is staged locally but
ignored by Git. The checked HPC archive is the canonical distributable binary
record for both final model families and the complete execution evidence.
