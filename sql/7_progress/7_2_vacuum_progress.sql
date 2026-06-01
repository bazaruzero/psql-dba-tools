-- vacuum

--
-- https://github.com/dataegret/pg-utils/blob/master/sql/vacuum_progress.sql
--

select
    p.pid,
    date_trunc('second',now() - coalesce(a.xact_start, a.query_start, a.backend_start)) as duration,
    case
        when wait_event is null then 'CPU'
        else wait_event_type||':'||wait_event
    end wait_event,
    case
        when a.query ~ 'to prevent wraparound' then 'freeze' 
        else 'regular'
    end as mode,
    (select datname from pg_database where oid = p.datid) as db,
    p.relid::regclass as table,
    p.phase,
    case p.phase
        when 'initializing' then '1 of 7'
        when 'scanning heap' then '2 of 7'
        when 'vacuuming indexes' then '3 of 7'
        when 'vacuuming heap' then '4 of 7'
        when 'cleaning up indexes' then '5 of 7'
        when 'truncating heap' then '6 of 7'
        when 'performing final cleanup' then '7 of 7'
    end as phase_num,
    pg_size_pretty(pg_relation_size(relid)) as table_size,
    pg_size_pretty(pg_total_relation_size(relid)) as total_table_size,
    pg_size_pretty((p.heap_blks_scanned * current_setting('block_size')::int)) as scanned,
    pg_size_pretty((p.heap_blks_vacuumed * current_setting('block_size')::int)) as vacuumed,
    (100 * p.heap_blks_scanned / nullif(p.heap_blks_total,0)) as scanned_pct,
    (100 * p.heap_blks_vacuumed / nullif(p.heap_blks_total,0)) as vacuumed_pct,
    p.index_vacuum_count as ind_vac_cnt,
    round(p.num_dead_tuples * 100.0 / nullif(p.max_dead_tuples, 0),1) as mwm_util_pct -- maintenance_work_mem_utilization
from
    pg_stat_progress_vacuum p
    left join pg_stat_activity a using (pid)
order by
    duration desc;