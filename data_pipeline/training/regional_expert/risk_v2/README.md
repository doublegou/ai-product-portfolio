# Regional Risk V2 data — Full50 + Process14

This pipeline appends the frozen 14-field Process14 manifest to the 372-row `himalaya_risk_v1.csv`. It does not rerun raw GIS extraction and does not alter any V1 column.

All Process14 definitions are frozen in `config/process14_formula_dictionary.yml` before any formal V2 model fit. They must not be changed after formal training begins.

The pipeline consumes the frozen V1 regional table, V1 response-blind branch map, Full50 manifest, Process14 field manifest, and formula dictionary. It writes:

- `data/processed/training/himalaya_risk_v2.csv`
- `data/processed/training/himalaya_risk_v2_manifest.json`

Run from the repository root:

```powershell
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" data_pipeline/training/regional_expert/risk_v2/scripts/run.R
```

This is a data-only stage. It performs no RF or shallow-boosting fit, no threshold selection, and no Failure Audit.
