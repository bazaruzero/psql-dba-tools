-- top tables

\echo ''
\echo '##'
\echo '## NOTE: use "table detailed info" section to get more information about specific table.'
\echo '##'
\echo ''

with table_sizes as (
    select
        c.relnamespace::regnamespace::text as tbl_schema,
        c.relname as tbl_name,
        case
            when c.reltoastrelid = 0 then pg_total_relation_size(c.oid) - pg_indexes_size(c.oid)
            else pg_total_relation_size(c.oid) - pg_indexes_size(c.oid) - pg_total_relation_size(c.reltoastrelid)
        end as tbl_size_bytes,
        case
            when (c.relispartition = 'f' or c.relispartition = 't') and c.relkind = 'p' then (select sum(pg_relation_size(pt.relid)) from pg_partition_tree(c.oid) pt where pt.level <> 0)
            else 0
        end as tbl_part_size_bytes,
        pg_indexes_size(c.oid) as tbl_idx_size_bytes,
        case
            when c.reltoastrelid = 0 then 0
            else pg_total_relation_size(c.reltoastrelid) - pg_indexes_size(c.reltoastrelid)
        end as tbl_toast_size_bytes,
        case
            when c.reltoastrelid = 0 then 0
            else pg_indexes_size(c.reltoastrelid)
        end as tbl_toast_idx_size_bytes,
        pg_total_relation_size(c.oid) as tbl_total_size_bytes
    from
        pg_class c
    where
        c.relkind in ('r')
)
select
    tbl_schema,
    tbl_name,
    pg_size_pretty(tbl_total_size_bytes) as tbl_total_size,
    pg_size_pretty(tbl_size_bytes) as tbl_size,
    pg_size_pretty(tbl_part_size_bytes) as tbl_part_size,
    pg_size_pretty(tbl_idx_size_bytes) as tbl_idx_size,
    pg_size_pretty(tbl_toast_size_bytes) as tbl_toast_size,
    pg_size_pretty(tbl_toast_idx_size_bytes) as tbl_toast_idx_size
from
    table_sizes
order by
    tbl_total_size_bytes desc
limit 10;