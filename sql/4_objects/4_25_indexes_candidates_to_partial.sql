-- index candidates to be replaced by partial indexes

-- ref. to  https://github.com/dataegret/pg-utils/blob/master/sql/index_candidates_to_partial.sql

-- single-column indexes where 5 or fewer distinct values cover 95+% of the
-- non-null rows -> likely replaceable with a partial (WHERE ...) index to save space

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
        st.most_common_freqs[1:5] as most_common_freqs,
        (st.most_common_vals::text::text[])[1:5] as most_common_vals,
        (select sum(f) from unnest(st.most_common_freqs[1:5]) as f) as top5_freq_sum,
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
        array_length(i.indkey, 1) = 1
        and pg_relation_size(c.oid) > 10 * 8192
        and (select sum(f) from unnest(st.most_common_freqs[1:5]) as f) >= 0.95
)
select
    idx_schema,
    idx_table,
    idx_field,
    idx_name,
    idx_type,
    idx_kind,
    round((null_frac * 100)::numeric, 1) as null_frac_pct,
    round((top5_freq_sum * 100)::numeric, 1) as top5_freq_pct,
    most_common_freqs,
    most_common_vals,
    pg_size_pretty(idx_size_bytes) as idx_size,
    idx_def
from
    index_data
order by
    idx_size_bytes desc,
    idx_schema,
    idx_table,
    idx_field
\gx