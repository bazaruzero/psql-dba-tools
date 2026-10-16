-- top partitioned tables

\echo ''
\echo '##'
\echo '## NOTE: use "table detailed info" section to get more information about specific table.'
\echo '##'
\echo ''

with part_tables as (
    select
        c.oid as part_oid,
        c.relnamespace::regnamespace::text as tbl_schema,
        c.relname as tbl_name
    from
        pg_class c
    where
        c.relkind = 'p'
),
subtree_sizes as (
    select
        pt.part_oid,
        pt.tbl_schema,
        pt.tbl_name,
        coalesce(sum(pg_total_relation_size(t.oid)), 0)::bigint as tbl_total_size_bytes,
        coalesce(sum(
            case
                when t.reltoastrelid = 0 then pg_total_relation_size(t.oid) - pg_indexes_size(t.oid)
                else pg_total_relation_size(t.oid) - pg_indexes_size(t.oid) - pg_total_relation_size(t.reltoastrelid)
            end
        ), 0)::bigint as tbl_size_bytes,
        coalesce(sum(
            case
                when l.level <> 0 then pg_relation_size(l.relid)
                else 0
            end
        ), 0)::bigint as tbl_part_size_bytes,
        coalesce(sum(pg_indexes_size(t.oid)), 0)::bigint as tbl_idx_size_bytes,
        coalesce(sum(
            case
                when t.reltoastrelid <> 0 then pg_total_relation_size(t.reltoastrelid) - pg_indexes_size(t.reltoastrelid)
                else 0
            end
        ), 0)::bigint as tbl_toast_size_bytes,
        coalesce(sum(
            case
                when t.reltoastrelid <> 0 then pg_indexes_size(t.reltoastrelid)
                else 0
            end
        ), 0)::bigint as tbl_toast_idx_size_bytes
    from
        part_tables pt
        cross join lateral pg_partition_tree(pt.part_oid) l
        join pg_class t on t.oid = l.relid
    group by
        pt.part_oid, pt.tbl_schema, pt.tbl_name
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
    subtree_sizes
order by
    tbl_total_size_bytes desc
limit 10;