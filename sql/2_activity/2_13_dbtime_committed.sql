-- completed query duration stats, i.e. "DBTime Committed" (pg_stat_statements required)

--
-- https://habr.com/ru/companies/vtb/articles/1011188/
--

select
    count(*)                                                                                                                          as total_queries,
  --coalesce(round(sum(calls)), 0)                                                                                                    as total_calls,
    coalesce(round(sum(mean_exec_time + mean_plan_time)), 0)                                                                          as total_avg_ms,
    coalesce(round(avg(mean_exec_time + mean_plan_time)), 0)                                                                          as avg_ms,
    coalesce(sum(case when (mean_exec_time + mean_plan_time) > 1000 then 1 else 0 end), 0)                                            as slow_queries,
    round(coalesce(100.0 * sum(case when (mean_exec_time + mean_plan_time) > 1000 then 1 else 0 end) / nullif(count(*), 0), 0), 2)    as slow_ratio,
    coalesce(round(max(max_exec_time + max_plan_time)), 0)                                                                            as max_ms
from
    pg_stat_statements(false)
\watch 1