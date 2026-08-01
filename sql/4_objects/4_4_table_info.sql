-- tables info (top-10 by total_size by default)

with db_size as (
    select pg_database_size(current_database()) as total_db_size
),
table_size as (
select
    c.relnamespace::regnamespace::text as table_schema,
    c.relname as table_name,
    case
        when c.relkind = 'p' then true
        else false
    end as is_partitioned,
    c.relispartition as is_partition,
    case
        when c.relispartition = 'f' and c.relkind = 'p' then 'root'
        when c.relispartition = 't' and c.relkind = 'p' then 'sub'
        when c.relispartition = 't' and c.relkind = 'r' then 'leaf'
        when c.relispartition = 'f' and c.relkind = 'r' then '-'
    end as partition_level,
    case
        when c.relispartition = 'f' and (c.relkind = 'r' OR c.relkind = 'p') then '-'
        else pg_get_partition_constraintdef(c.oid)::text
    end as partition_bound,
    case
        when (c.relispartition = 'f' or c.relispartition = 't') and c.relkind = 'r' then '-'
        else pg_get_partkeydef(c.oid)
    end as partition_key,
    case
        when (c.relispartition = 'f' or c.relispartition = 't') and c.relkind = 'p' then (select count(*) from pg_partition_tree(c.oid) pt where pt.level <> 0)
        else 0
    end as partition_count,
    case
        when c.reltoastrelid = 0 then pg_total_relation_size(c.oid) - pg_indexes_size(c.oid)
        else pg_total_relation_size(c.oid) - pg_indexes_size(c.oid) - pg_total_relation_size(c.reltoastrelid)
    end as tbls,
    case
        when (c.relispartition = 'f' or c.relispartition = 't') and c.relkind = 'p' then (select sum(pg_relation_size(pt.relid)) from pg_partition_tree(c.oid) pt where pt.level <> 0)
        else 0
    end as tps,
    pg_indexes_size(c.oid) as idxs,
    case
        when c.reltoastrelid = 0 then 0
        else pg_total_relation_size(c.reltoastrelid) - pg_indexes_size(c.reltoastrelid)
      end as ttbls,
    case
        when c.reltoastrelid = 0 then 0
        else pg_indexes_size(c.reltoastrelid)
      end as tidxs,
    pg_total_relation_size(c.oid) as ts,
    t.n_live_tup,
    t.n_dead_tup,
    case                                                                    
        when t.n_live_tup + t.n_dead_tup > 0 
        then round((t.n_dead_tup::numeric / (t.n_live_tup + t.n_dead_tup) * 100), 2) 
        else 0 
    end as dead_pct,
    t.last_vacuum, 
    t.last_analyze, 
    t.last_autovacuum, 
    t.last_autoanalyze,
    c.reloptions
from 
    pg_class c
    join pg_stat_user_tables t on c.oid = t.relid
where
    1 = 1
    and c.relkind in ('r','p')
    --and c.relnamespace::regnamespace::text = 'myschema'
    --and c.relname = 'mytable'
),
result as (
    select
        t.*,
        d.total_db_size,
        round(100.0 * t.ts / nullif(d.total_db_size, 0), 2) as db_size_pct,
        round(100.0 * t.ts / nullif(sum(t.ts) over (partition by t.table_schema), 0), 2) as schema_size_pct
    from
        table_size t
        cross join db_size d
)
select
    table_schema,
    table_name,
    is_partitioned,
    is_partition,
    partition_level,
    partition_bound,
    partition_key,
    partition_count,
    reloptions as table_settings,
    pg_size_pretty(tbls) as table_size,
    pg_size_pretty(tps) as table_partitions_size,
    pg_size_pretty(idxs) as idx_size,
    pg_size_pretty(ttbls) as toast_table_size,
    pg_size_pretty(tidxs) as toast_idx_size,
    pg_size_pretty(ts) as total_size,
    db_size_pct,
    schema_size_pct,
    n_live_tup,
    n_dead_tup,
    dead_pct,
    last_vacuum,
    last_analyze,
    last_autovacuum,
    last_autoanalyze
from
    result
order by
    ts desc
limit 10;
