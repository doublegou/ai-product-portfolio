-- Full public-state comparison exceeds the API's default 8s on this dataset.
-- Limit the exemption to this private RPC, rather than all service-role calls.
alter function public.export_snapshot_batch(boolean) set statement_timeout='30s';
notify pgrst, 'reload schema';
