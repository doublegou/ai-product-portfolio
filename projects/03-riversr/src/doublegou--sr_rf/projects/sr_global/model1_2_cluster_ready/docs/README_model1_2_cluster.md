# Model 1-2 cluster-ready workflow

This folder contains a cleaned HPC version of the first two steps:

1. `01_filter_solute_and_pilot_points.R`
   - Reads `data_raw/water/world_river_water_sr.csv`
   - Keeps `sample_type == solute`
   - Extracts Pearl River / South China pilot points
   - Saves CSV/RDS/GPKG and a pilot point map

2. `02_model1_2_spatial_hydro_baselines.R`
   - Reads the Step 1 RDS output
   - Reads HydroRIVERS shapefile from `data_raw/hydrosheds/HydroRIVERS/`
   - Snaps points to nearest river segment
   - Builds Model 1-2 baseline dataframe
   - Runs linear spatial, RF spatial, RF HydroRIVERS, RF spatial+HydroRIVERS
   - Saves metrics, figures, and model objects

## Expected cluster paths

Project root:

```bash
/home/zhangmeng/projects/sr_global
```

Input files:

```bash
data_raw/water/world_river_water_sr.csv
data_raw/hydrosheds/HydroRIVERS/<whole shapefile folder, including .shp .dbf .shx .prj>
```

## Run

```bash
cd ~/projects/sr_global
sbatch slurm/run_model1_2_step1.sbatch
sbatch slurm/run_model1_2_step2.sbatch
```

or run both steps in one job:

```bash
sbatch slurm/run_model1_2_all.sbatch
```

Check logs:

```bash
cat logs/m12_step1_*.out
cat logs/m12_step1_*.err
cat logs/m12_step2_*.out
cat logs/m12_step2_*.err
```
