-- top sql by STDDEV (pg_stat_statements required)

with all_stats as (
    select
        coalesce(sum(total_plan_time + total_exec_time), 0)::numeric as total_db_time,
        coalesce(sum(calls), 0)::numeric as total_calls
    from pg_stat_statements(false)
    where 
        (total_plan_time + total_exec_time) > 0 
        and calls > 0
),
filtered_stats as (
    select
        queryid,
        sum(total_plan_time + total_exec_time)::numeric as db_time,
        sum(calls)::numeric as calls_count,
        avg(mean_exec_time)::numeric as avg_time,
        avg(stddev_exec_time)::numeric as avg_stddev,
        min(min_exec_time)::numeric as min_time,
        max(max_exec_time)::numeric as max_time,
        (avg(stddev_exec_time) / nullif(avg(mean_exec_time), 0)) as instability_raw,
        (max(max_exec_time) / nullif(avg(mean_exec_time), 0)) as degradation_raw
    from
        pg_stat_statements(false)
    group by
        queryid
    having
        avg(mean_exec_time) > 1
        and (
            (avg(stddev_exec_time) / nullif(avg(mean_exec_time), 0)) > 1.5 
            or (max(max_exec_time) / nullif(avg(mean_exec_time), 0)) > 3
        )
)
select
    fs.queryid,
    case 
        when ast.total_db_time > 0 
        then round((fs.db_time / ast.total_db_time) * 100, 2)
        else 0
    end as t_db_time_pct,
    round(fs.db_time, 2) as t_db_time_ms,
    case 
        when ast.total_calls > 0 
        then round((fs.calls_count / ast.total_calls) * 100, 2)
        else 0
    end as t_calls_pct,
    fs.calls_count::bigint as t_calls,
    round(fs.avg_time, 3) as avg_exec_time_ms,
    round(fs.avg_stddev, 3) as avg_stddev_ms,
    round(fs.min_time, 2) as min_exec_time_ms,
    round(fs.max_time, 2) as max_exec_time_ms,
    round(fs.instability_raw::numeric, 2) as instability,
    round(fs.degradation_raw::numeric, 2) as degradation
from
    filtered_stats fs
cross join all_stats ast
order by
    degradation desc,
    instability desc
limit 10;