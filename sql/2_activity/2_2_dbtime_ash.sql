-- active query duration stats (DBTime ASH)

--
-- https://habr.com/ru/companies/vtb/articles/1011188/
--

--
-- total_queries - number of queries(sessions) currently running (excluding idle & background)
-- total_ms      - sum of durations of all active queries (Active DBTime)
-- avg_ms        - average duration across all active queries
-- p50_ms        - median, i.e. 50% of queries finish faster than this value
-- p90_ms        - 90th percentile, i.e. 90% of queries finish faster
-- p95_ms        - 95th percentile, i.e. 95% of queries finish faster
-- p99_ms        - 99th percentile (tail latency), i.e. 99% of queries finish faster
-- max_ms        - longest currently running query
--

select
    count(*) as total_queries,
    coalesce(sum(duration), 0) as total_ms,
    round(coalesce(avg(duration), 0)) as avg_ms,
    round(coalesce((percentile_cont(0.5) within group (order by duration)),0)) as p50_ms,
    round(coalesce((percentile_cont(0.9) within group (order by duration)),0)) as p90_ms,
    round(coalesce((percentile_cont(0.95) within group (order by duration)),0)) as p95_ms,
    round(coalesce((percentile_cont(0.99) within group (order by duration)),0)) as p99_ms,
    round(coalesce(max(duration), 0)) as max_ms
from (
    select
        greatest(coalesce(extract(epoch from (clock_timestamp() - a.query_start) * 1000)::bigint,0),0) as duration
    from 
        pg_stat_activity a
    where 1=1
        and pid <> pg_backend_pid()
        and a.state <> 'idle'
        and a.backend_type = 'client backend'
) t
\watch 1