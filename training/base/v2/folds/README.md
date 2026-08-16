# Base V2 frozen folds

This directory is generated only by:

```powershell
Rscript training/base/v2/scripts/run.R --stage prepare
```

It freezes the response-blind Small/Primary/Large branch reconstruction, the selected Primary membership, every task-specific downstream purge role, nested Inner assignments, deployment assignments, fixed stress assignments, diagnostics, and provenance hashes. After preparation, formal training consumes only the Full50 table plus this directory.

Current forward reconstruction:

- Small: 324 branches / 2,139 eligible rows; maximum 9 stations per branch.
- Primary: 221 branches / 2,577 eligible rows; maximum 19 stations per branch.
- Large: 125 branches / 2,707 eligible rows; maximum 39 stations per branch.
- Primary Outer assessment: 514–519 rows per fold.
- Primary Outer downstream purge: 114–201 rows per fold across three repeats.

The preserved historical values (approximately 219 branches, 2,568 eligible rows, 511–515 assessment rows and 197–270 purge rows) are scale anchors, not exact membership truth. Unlike the superseded Pfaf-prefix reconstruction, station-frontier branches cannot absorb 322 stations from hundreds of L12 units into one validation unit. `branch_relations.csv` records only relations between two eligible branch units; downstream connections from an eligible branch into training-support rows are represented directly by the frozen `role=purged_downstream` assignments.
