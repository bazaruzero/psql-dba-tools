-- top sql by DBTime (pg_stat_statements required)

select
    queryid,
    -- db time
    case
        when round((sum((total_plan_time + total_exec_time)::numeric) / nullif(sum(sum((total_plan_time + total_exec_time)::numeric)) over (),0)) * 100, 2) is null then 0
        else round((sum((total_plan_time + total_exec_time)::numeric) / nullif(sum(sum((total_plan_time + total_exec_time)::numeric)) over (),0)) * 100, 2)
    end "t_db_time_%",
    round(sum(total_exec_time::numeric), 2) as t_db_time_ms,
    -- cpu
    case
        when round((sum(total_plan_time + total_exec_time - blk_read_time - blk_write_time)::numeric / nullif(sum(sum(total_plan_time + total_exec_time - blk_read_time - blk_write_time)::numeric) over (),0)) * 100, 2) is null then 0
        else round((sum(total_plan_time + total_exec_time - blk_read_time - blk_write_time)::numeric / nullif(sum(sum(total_plan_time + total_exec_time - blk_read_time - blk_write_time)::numeric) over (),0)) * 100, 2)
    end "t_cpu_%", -- CPU and Non-IO-Waits(lwlocks, hwlocks, etc)
    round(sum(total_plan_time + total_exec_time - blk_read_time - blk_write_time)::numeric, 2) as "t_cpu_time_ms",
    -- io
    case
        when round((sum(blk_read_time + blk_write_time)::numeric / nullif(sum(sum(blk_read_time + blk_write_time)::numeric) over (),0)) * 100, 2) is null then 0
        else round((sum(blk_read_time + blk_write_time)::numeric / nullif(sum(sum(blk_read_time + blk_write_time)::numeric) over (),0)) * 100, 2)
    end "t_io_%",
    round(sum(blk_read_time + blk_write_time)::numeric, 2) as "t_io_time_ms",
    -- calls
    case
        when round((sum(calls::numeric) / nullif(sum(sum(calls::numeric)) over (),0)) * 100, 2) is null then 0
        else round((sum(calls::numeric) / nullif(sum(sum(calls::numeric)) over (),0)) * 100, 2)
    end "t_calls_%",
    sum(calls) as t_calls,
    -- wal
    /***
    case
        when round((sum(wal_records::numeric) / nullif(sum(sum(wal_records::numeric)) over (),0)) * 100, 2) is null then 0
        else round((sum(wal_records::numeric) / nullif(sum(sum(wal_records::numeric)) over (),0)) * 100, 2)
    end "t_wal_rec_%",
    round(sum(wal_records::numeric), 2) as "t_wal_records",
    case
        when round((sum(wal_fpi::numeric) / nullif(sum(sum(wal_fpi::numeric)) over (),0)) * 100, 2) is null then 0
        else round((sum(wal_fpi::numeric) / nullif(sum(sum(wal_fpi::numeric)) over (),0)) * 100, 2)
    end "t_wal_fpi_%",
    round(sum(wal_fpi::numeric), 2) as "t_wal_fpi",
    ***/
    case
        when round((sum(wal_bytes::numeric) / nullif(sum(sum(wal_bytes::numeric)) over (),0)) * 100, 2) is null then 0
        else round((sum(wal_bytes::numeric) / nullif(sum(sum(wal_bytes::numeric)) over (),0)) * 100, 2)
    end "t_wal_size_%",
    pg_size_pretty(sum(wal_bytes::numeric)) as "t_wal_size",
    round(avg(mean_exec_time)::numeric,3) as "avg_exec_time_ms",
    round(avg(stddev_exec_time)::numeric,3) as "avg_stddev_exec_time_ms"
from
    pg_stat_statements(false)
group by
    queryid
order by
    -- db time
        sum(total_plan_time + total_exec_time) desc
    -- cpu
        --sum(total_plan_time + total_exec_time - blk_read_time - blk_write_time) desc
    -- io
        --sum(blk_read_time + blk_write_time) desc
    -- calls
        --sum(calls) desc
    -- wal
        --sum(wal_bytes) desc
limit
    10
;