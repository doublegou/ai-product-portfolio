# Frozen Risk V1 folds

`inner_assignments.csv` contains the risk-specific 3-fold grouped Inner design for each of the 15 frozen Base V1 Outer training sets. `task_manifest.csv` expands those Outer tasks across the two model families (30 tasks). `fold_manifest.json` records source signatures and construction rules.

The Outer assignments are not copied: `config/default.yml` points directly to the authoritative Base V1 frozen file. Rebuilding is prohibited after any validation task exists.
