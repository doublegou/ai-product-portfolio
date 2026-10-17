-- CREATE OR REPLACE with SET search_path replaces the function's settings.
-- Retain the private export RPC's existing timeout after the budget change.
alter function public.export_snapshot_batch(boolean) set statement_timeout='30s';
notify pgrst, 'reload schema';
