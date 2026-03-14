-- heavyweight locks

-- https://postgres.ai/docs/postgres-howtos/performance-optimization/monitoring/how-to-analyze-heavyweight-locks-part-1

select
    mode||':'||granted||':'||fastpath as mode_granted_fastpath,
    count(*) as sess_count,
    round(100.0 * count(*) / sum(count(*)) over ()) as pct_hw_locks
from
    pg_locks
where
    1 = 1
    and locktype <> 'virtualxid'
    and pid <> pg_backend_pid()
group by
    mode, granted, fastpath
order by
    sess_count desc;