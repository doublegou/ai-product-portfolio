-- Change export cadence only; collection schedules and the daily byte cap stay intact.
select cron.alter_job(job_id:=jobid,schedule:='*/30 * * * *')
from cron.job where jobname='pricemapai-publish-snapshot';
