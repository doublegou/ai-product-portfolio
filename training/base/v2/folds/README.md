# Base V2 frozen folds

This directory is generated only by:

```powershell
Rscript training/base/v2/scripts/run.R --stage prepare
```

It freezes the response-blind Small/Primary/Large branch reconstruction, the selected Primary membership, every task-specific downstream purge role, nested Inner assignments, deployment assignments, fixed stress assignments, diagnostics, and provenance hashes. After preparation, formal training consumes only the Full50 table plus this directory.

Current forward reconstruction:

- Small: 390 branches / 2,749 eligible rows.
- Primary: 243 branches / 2,646 eligible rows.
- Large: 174 branches / 2,649 eligible rows.
- Primary Outer assessment: 528–530 rows per fold.
- Primary Outer downstream purge: 134–227 rows per fold across three repeats.

The preserved historical values (approximately 219 branches, 2,568 eligible rows, 511–515 assessment rows and 197–270 purge rows) are scale anchors, not exact membership truth. `branch_relations.csv` records only relations between two eligible branch units; downstream connections from an eligible branch into training-support rows are represented directly by the frozen `role=purged_downstream` assignments.
