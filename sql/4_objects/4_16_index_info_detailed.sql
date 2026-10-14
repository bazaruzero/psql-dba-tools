-- index info detailed (adjust filter inside "target_index" CTE)

\echo ''
\echo '##'
\echo '## NOTE: uncomment "c.relnamespace::regnamespace::text =" line in "target_index" CTE'
\echo '##       to additionally restrict by schema. Index name filter is required.'
\echo '##'
\echo ''

with target_index as (
    select
        c.oid as idx_oid,
        c.reloptions,
        c.relnamespace::regnamespace::text as idx_schema,
        c.relname as idx_name,
        case
            when c.reltablespace <> 0 then (select ts.spcname from pg_tablespace ts where ts.oid = c.reltablespace)
            else (select ts.spcname from pg_database d, pg_tablespace ts where d.datname = current_database() and d.dattablespace = ts.oid)
        end as tablespace,
        case
            when c.reltablespace <> 0 then
                coalesce(
                    nullif(pg_tablespace_location(c.reltablespace), ''),
                    current_setting('data_directory') || '/base'
                )
            else (
                select
                    coalesce(
                        nullif(pg_tablespace_location(d.dattablespace), ''),
                        current_setting('data_directory') || '/base'
                    )
                from pg_database d
                where d.datname = current_database()
            )
        end as tablespace_path
    from pg_class c
    where
        c.relkind in ('i', 'I', 'G')
        --and c.relnamespace::regnamespace::text = 'myschema'
        and c.relname in ('my_index', 'my_index_p1')
),
table_link as (
    select
        ti.idx_oid,
        tc.relnamespace::regnamespace::text as tbl_schema,
        tc.relname as tbl_name
    from
        target_index ti
        join pg_index i on i.indexrelid = ti.idx_oid
        join pg_class tc on tc.oid = i.indrelid
),
index_metadata as (
    select
        ti.idx_oid,
        am.amname as idx_type,
        case c.relkind
            when 'i' then 'local'
            when 'I' then 'partitioned'
            when 'G' then 'global'
            else c.relkind::text
        end as idx_kind,
        i.indisvalid as is_valid,
        i.indisready as is_ready,
        i.indisunique as is_unique,
        i.indisprimary as is_primary,
        pg_get_indexdef(ti.idx_oid) as idx_def,
        coalesce(pg_get_expr(i.indpred, i.indrelid), '-') as idx_predicate,
        coalesce(
            (select v[1] from regexp_matches(c.reloptions::text, E'fillfactor=(\\d+)') as r(v) limit 1),
            '90'
        )::int as fillfactor
    from
        target_index ti
        join pg_class c on c.oid = ti.idx_oid
        join pg_index i on i.indexrelid = ti.idx_oid
        join pg_am am on c.relam = am.oid
),
constraint_info as (
    select
        cn.conindid as idx_oid,
        string_agg(cn.conname, ', ' order by cn.conname) as constraint_name
    from
        target_index ti
        join pg_constraint cn on cn.conindid = ti.idx_oid
    group by
        cn.conindid
)
select
    tgt.idx_schema,
    -- tablespace name; falls back to DB default tablespace if not set
    tgt.tablespace as idx_tablespace,
    -- filesystem path of the tablespace
    tgt.tablespace_path as idx_tablespace_path,
    tgt.idx_name,
    im.idx_type,
    im.idx_kind,
    -- backing table schema and name
    tl.tbl_schema,
    tl.tbl_name,
    im.is_valid,
    im.is_ready,
    im.is_unique,
    im.is_primary,
    -- full index DDL
    im.idx_def,
    -- partial index predicate, '-' if the index is not partial
    im.idx_predicate,
    -- constraint backed by this index, '-' if none
    coalesce(ci.constraint_name, '-') as constraint_name,
    -- total index size
    pg_size_pretty(pg_total_relation_size(tgt.idx_oid)) as idx_size,
    st.idx_scan,
    st.idx_tup_read,
    st.idx_tup_fetch,
    -- effective fillfactor; btree default 90 is shown when not overridden
    im.fillfactor,
    tgt.reloptions as idx_settings,
    -- time of the last statistics reset for the database (NULL = never reset)
    (select stats_reset from pg_stat_database where datname = current_database()) as stats_reset
from
    target_index tgt
    join table_link tl on tl.idx_oid = tgt.idx_oid
    join index_metadata im on im.idx_oid = tgt.idx_oid
    left join constraint_info ci on ci.idx_oid = tgt.idx_oid
    left join pg_stat_all_indexes st on st.indexrelid = tgt.idx_oid
\gx