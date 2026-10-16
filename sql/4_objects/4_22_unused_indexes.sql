-- unused indexes 

-- ref. to https://postgres.ai/docs/postgres-howtos/performance-optimization/indexing/how-to-find-unused-indexes

with unused_indexes as (
    select
        s.schemaname as idx_schema,
        t.relname as idx_table,
        c.relname as idx_name,
        am.amname as idx_type,
        case c.relkind
            when 'i' then 'local'
            when 'I' then 'partitioned'
            when 'G' then 'global'
            else c.relkind::text
        end as idx_kind,
        s.idx_scan,
        i.indisunique as is_unique,
        pg_relation_size(s.indexrelid) as idx_size_bytes
    from
        pg_stat_user_indexes s
        join pg_index i on i.indexrelid = s.indexrelid
        join pg_class c on c.oid = s.indexrelid
        join pg_class t on t.oid = i.indrelid
        join pg_am am on am.oid = c.relam
    where
        s.idx_scan = 0
        and not i.indisunique
),
unused_indexes_report as (
    select
        idx_schema,
        idx_table,
        idx_name,
        idx_type,
        idx_kind,
        idx_scan,
        is_unique,
        idx_size_bytes,
        0 as sort_order
    from
        unused_indexes
    union all
    select
        'total',
        '',
        '',
        '',
        '',
        sum(idx_scan),
        null,
        sum(idx_size_bytes)::bigint,
        1 as sort_order
    from
        unused_indexes
)
select
    (select stats_reset from pg_stat_database where datname = current_database()) as stats_reset,
    idx_schema,
    idx_table,
    idx_name,
    idx_type,
    idx_kind,
    idx_scan,
    is_unique,
    pg_size_pretty(idx_size_bytes) as idx_size
from
    unused_indexes_report
order by
    sort_order,
    idx_size_bytes desc
;