-- tables with seq scan

-- ref. to https://github.com/dataegret/pg-utils/blob/master/sql/seq_scan_tables.sql

with seq_scan_tables as (
    select
        s.schemaname ||'.'|| s.relname as tbl_name,
        case when c.relkind = 'p' then true else false end as is_partitioned,
        c.relispartition as is_partition,
        s.n_live_tup,
        case
            when c.relkind = 'p' then (
                select coalesce(sum(pg_total_relation_size(t.oid)), 0)::bigint
                from pg_partition_tree(s.relid) l
                join pg_class t on t.oid = l.relid
            )
            else pg_total_relation_size(s.relid)
        end as tbl_total_size_bytes,
        s.seq_scan,
        s.seq_tup_read,
        (coalesce(s.n_tup_ins, 0) + coalesce(s.n_tup_upd, 0) + coalesce(s.n_tup_del, 0)) as write_activity
        --(select count(*) from pg_index pi where pi.indrelid = s.relid) as index_count,
        --s.idx_scan,
        --s.idx_tup_fetch
    from
        pg_stat_all_tables s
        join pg_class c on c.oid = s.relid
    where
        s.seq_scan > 0
        and s.seq_tup_read > 100000
        and s.schemaname <> 'pg_catalog'
)
select
    (select stats_reset from pg_stat_database where datname = current_database()) as stats_reset,
    tbl_name,
    is_partitioned,
    is_partition,
    n_live_tup,
    pg_size_pretty(tbl_total_size_bytes) as tbl_total_size,
    seq_scan,
    pg_size_pretty(seq_scan * tbl_total_size_bytes) as seq_scan_size,
    seq_tup_read,
    write_activity
    --index_count,
    --idx_scan,
    --idx_tup_fetch
from
    seq_scan_tables
order by
    (seq_scan * tbl_total_size_bytes) desc
limit 20;