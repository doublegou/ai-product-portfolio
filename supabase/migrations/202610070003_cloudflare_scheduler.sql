-- Cloudflare now invokes the Worker's scheduled handler directly.
-- Keep the former HTTP job inactive for a reversible fallback.
select cron.alter_job(jobid, active := false)
from cron.job
where jobname = 'aimarketing-price-refresh';

-- aimarketing-log-retention remains active in Supabase.
