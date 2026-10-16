-- indexes with NULLs (null fraction over 50%)

-- ref. to https://github.com/dataegret/pg-utils/blob/master/sql/indexes_with_nulls.sql

with index_data as (
    select
        c.relnamespace::regnamespace::text as idx_schema,
        t.relname as idx_table,
        c.relname as idx_name,
        a.attname as idx_field,
        am.amname as idx_type,
        case c.relkind
            when 'i' then 'local'
            when 'I' then 'partitioned'
            when 'G' then 'global'
            else c.relkind::text
        end as idx_kind,
        st.null_frac,
        pg_relation_size(c.oid) as idx_size_bytes,
        pg_get_indexdef(c.oid) as idx_def
    from
        pg_index i
        join pg_class c on c.oid = i.indexrelid
        join pg_class t on t.oid = i.indrelid
        join pg_am am on am.oid = c.relam
        join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
        join pg_stats st
            on st.schemaname = t.relnamespace::regnamespace::text
            and st.tablename = t.relname
            and st.attname = a.attname
    where
        st.null_frac > 0.5
        and pg_relation_size(c.oid) > 10 * 8192
)
select
    idx_schema,
    idx_table,
    idx_name,
    idx_field,
    idx_type,
    idx_kind,
    round((null_frac * 100)::numeric, 1) as null_frac_pct,
    pg_size_pretty(idx_size_bytes) as idx_size
    -- ,idx_def
from
    index_data
order by
    idx_size_bytes desc,
    idx_schema,
    idx_table,
    idx_field
;