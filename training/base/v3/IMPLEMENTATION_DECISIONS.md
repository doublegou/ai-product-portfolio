# Base V3 implementation decisions

1. **Hydrological system.** Level-6 station IDs are joined to the official
   HydroBASINS `MAIN_BAS` attribute. The current release contains 364 systems,
   including 13 systems with Sr `>=0.75` and five with Sr `>=0.80`.
2. **Balanced grouped folds.** Whole groups are greedily assigned with station
   count as the primary balance target and upper-tail counts as secondary
   targets. Three seeds create distinct Outer repeats; every Outer training set
   receives its own five-fold Inner assignment.
3. **Spatial stress groups.** Station coordinates are projected to EPSG:6933
   and grouped into square blocks of 500, 1,000 or 1,500 km.
4. **Reference stress groups.** `reference_id` is the indivisible group.
5. **RF pool.** `7 mtry × 9 min_node_size × 2 replace × 3 sample_fraction =
   378` structures.
6. **XGBoost pool.** `4 max_depth × 3 eta × 3 min_child_weight × 3 subsample ×
   2 colsample_bytree × 2 lambda × 2 alpha × 2 gamma = 1,728` structures.
7. **Coarse coverage.** Forty-eight structures are selected per Outer task by
   seeded maximin sampling in normalized parameter space.
8. **Refinement.** The four best coarse structural anchors seed a
   nearest-neighbour selection of 16 unique structures from the complete pool.
9. **Candidate selection.** Global RMSE is primary. Candidates within 0.5% of
   the best pooled Inner-OOF RMSE are ordered by extreme/high-system detection,
   extreme/high-site detection, low-background false-high rate, high-tail bias,
   global absolute bias, MAE and stable candidate ID.
10. **XGBoost early stopping.** Inner validation uses at most 3,000 rounds with
    50 rounds patience. The median selected Inner iteration is frozen for the
    Outer refit and deployment round count.
11. **Deployment recipe.** Up to 16 structures supported across the 15 Primary
    task refinement summaries are compared in a five-fold full-data grouped
    tuning pass. This pass selects a recipe only; Primary Nested OOF remains the
    performance estimate.
12. **Algorithm decision.** Pooled strict Outer-OOF RMSE is primary; MAE and
    absolute bias are deterministic tie-breakers. Both algorithms receive
    fixed-recipe stress tests.
13. **Hash contract.** Text inputs use LF-normalized SHA-256 so Windows and Linux
    checkouts have the same identity. Prepared and binary artifacts use raw-byte
    SHA-256. The R environment requires `bit64` for 64-bit basin identifiers.

Changing any decision requires a new run ID and a new config/source hash.
