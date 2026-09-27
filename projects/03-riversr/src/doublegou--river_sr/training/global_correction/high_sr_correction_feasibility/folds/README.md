# Frozen task manifests

`prepare` validates the already-frozen Base V1 grouped Outer/Inner assignments and writes only portable task manifests plus their signatures here. `base_fit_plan.csv` freezes all 240 canonical Base-fit keys and seeds before training. It does not create a new scientific split. Cluster jobs must use the committed manifests and must run `--stage check`, never `--stage prepare`.
