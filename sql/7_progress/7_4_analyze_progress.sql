-- analyze

select
    p.pid,
    date_trunc('second', now() - coalesce(a.xact_start, a.query_start, a.backend_start)) as duration,
    case
        when wait_event is null then 'CPU'
        else wait_event_type||':'||wait_event
    end wait_event,
    case
        when a.state = 'active' then 'active'
        when a.state = 'idle' then 'idle'
        else a.state
    end as state,
    (select datname from pg_database where oid = p.datid) as db,
    p.relid::regclass as table,
    p.phase,
    case p.phase
        when 'initializing' then '1 of 6'
        when 'acquiring sample rows' then '2 of 6'
        when 'acquiring inherited sample rows' then '3 of 6'
        when 'computing statistics' then '4 of 6'
        when 'computing extended statistics' then '5 of 6'
        when 'finalizing analyze' then '6 of 6'
    end as phase_num,
    pg_size_pretty(pg_relation_size(relid)) as table_size,
    pg_size_pretty(pg_total_relation_size(relid)) as total_table_size,
    case
        when p.current_child_table_relid > 0 
        then 'child: '||p.current_child_table_relid::regclass
        else ''
    end as current_child,
    case when p.sample_blks_total > 0 then round(100 * (p.sample_blks_scanned::numeric / p.sample_blks_total ), 2) else 0 end as blocks_pct,
    case when p.ext_stats_total > 0 then round(100 * (p.ext_stats_computed::numeric / p.ext_stats_total ), 2) else 0 end as extended_pct,
    case when p.child_tables_total > 0 then round(100 * (p.child_tables_done::numeric / p.child_tables_total), 2) else 0 end as child_pct
from
    pg_stat_progress_analyze p
    left join pg_stat_activity a using (pid)
order by
    duration desc;