# Global river-water Sr Stage 1

This package prepares global solute samples, snaps them to nine regional HydroRIVERS files with a Slurm array, and merges overlapping regional candidates by minimum geodesic distance.

## Install

From `/home/zhangmeng/projects/sr_global`:

```bash
cp -r global_stage1_snap_cluster_ready/scripts/* scripts/
cp -r global_stage1_snap_cluster_ready/slurm/* slurm/
cp -r global_stage1_snap_cluster_ready/config/* config/
chmod +x slurm/*.sbatch
```

## Run

```bash
sbatch slurm/01_prepare_global_samples.sbatch
```

After it succeeds:

```bash
sbatch slurm/02_snap_global_regions_array.sbatch
```

After all nine array tasks succeed:

```bash
sbatch slurm/03_merge_global_snaps.sbatch
```

Main output: `data_processed/global/global_model2_df_clean_5km.rds`.
