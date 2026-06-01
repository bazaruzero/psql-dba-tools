-- copy

select
    p.pid,
    date_trunc('second', now() - coalesce(a.xact_start, a.query_start, a.backend_start)) as duration,
    p.datname as db,
    pg_size_pretty(pg_database_size(p.datname)) as db_size,
    p.relid::regclass::text as relation,
    pg_size_pretty(pg_relation_size(p.relid)) as rel_size,
    pg_size_pretty(pg_total_relation_size(p.relid)) as total_rel_size,
    p.command,
    p.type,
    case
        when p.bytes_total <> 0 then (abs(round(100 * (p.bytes_processed::numeric / p.bytes_total), 2)))::text || '%'
        else pg_size_pretty(p.bytes_processed)
    end as bytes_pct
from
    pg_stat_progress_copy p
    left join pg_stat_activity a on a.pid = p.pid
;