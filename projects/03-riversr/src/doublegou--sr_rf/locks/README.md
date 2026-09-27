# Conda platform locks

`bootstrap.sh` looks here for a platform-specific explicit Conda lock:

- `conda-osx-arm64.lock`
- `conda-osx-64.lock`
- `conda-linux-64.lock`
- `conda-linux-aarch64.lock`

If a matching lock is absent, bootstrap falls back to
`river_sr_isoscape_v2_cluster/environment.yml`. A tested lock is generated after
the environment has been created successfully on that platform.

