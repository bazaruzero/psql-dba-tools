-- duplicate indexes

with idx_data as (
    select
        t.relnamespace::regnamespace::text as idx_schema,
        t.relname as idx_table,
        c.relname as idx_name,
        am.amname as idx_type,
        pg_total_relation_size(c.oid) as idx_size_bytes,
        i.indrelid as idx_table_oid,
        i.indkey::text as idx_columns,
        (
            select string_agg(a.attname, ', ' order by k.ord)
            from unnest(i.indkey::int2[]) with ordinality as k(attnum, ord)
            join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
        ) as idx_key
    from
        pg_index i
        join pg_class c on c.oid = i.indexrelid
        join pg_class t on t.oid = i.indrelid
        join pg_am am on am.oid = c.relam
    where
        c.relkind in ('i', 'G')
),
duplicate_indexes as (
    select
        min(idx_schema) as idx_schema,
        min(idx_table) as idx_table,
        min(idx_type) as idx_type,
        min(idx_key) as idx_key,
        string_agg(idx_name, ', ' order by idx_name) as idx_names,
        sum(idx_size_bytes)::bigint as idx_total_size_bytes,
        count(*) as idx_count
    from
        idx_data
    group by
        idx_table_oid, idx_columns
    having
        count(*) > 1
)
select
    idx_schema,
    idx_table,
    idx_names,
    idx_type,
    idx_key,
    idx_count,
    pg_size_pretty(idx_total_size_bytes) as idx_total_size
from
    duplicate_indexes
order by
    idx_total_size_bytes desc
;