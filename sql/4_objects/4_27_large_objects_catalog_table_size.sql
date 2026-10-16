-- large objects catalog table sizes (pg_largeobject, pg_largeobject_metadata)

-- ref. to
--    https://www.ludovicocaldara.net/blog/pgsql-lo-space-usage-part-1/
--    https://www.ludovicocaldara.net/blog/pgsql-lo-space-usage-part-2/
--    https://www.ludovicocaldara.net/blog/pgsql-lo-space-usage-part-3/
--    https://www.percona.com/blog/how-to-remove-an-orphan-large-object-in-postgresql-with-vacuumlo/

with target_table as (
    select
        c.oid as tbl_oid,
        c.relnamespace::regnamespace::text as tbl_schema,
        c.relname as tbl_name,
        -- tablespace name; falls back to DB default tablespace if not set
        case
            when c.reltablespace <> 0 then (select ts.spcname from pg_tablespace ts where ts.oid = c.reltablespace)
            else (select ts.spcname from pg_database d, pg_tablespace ts where d.datname = current_database() and d.dattablespace = ts.oid)
        end as tbl_tablespace,
        -- filesystem path of the tablespace
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
        end as tbl_tablespace_path
    from pg_class c
    where
        c.relnamespace = 'pg_catalog'::regnamespace
        and c.relname in ('pg_largeobject', 'pg_largeobject_metadata')
),
sizes as (
    select
        tgt.tbl_oid,
        pg_total_relation_size(tgt.tbl_oid) as tbl_total_size_bytes,
        pg_relation_size(tgt.tbl_oid) as tbl_size_bytes,
        pg_indexes_size(tgt.tbl_oid) as tbl_idx_size_bytes
    from target_table tgt
),
user_stats as (
    select
        s.relid as tbl_oid,
        s.n_live_tup,
        s.n_dead_tup
    from pg_stat_all_tables s
)
select
    tgt.tbl_schema,
    tgt.tbl_name,
    tgt.tbl_tablespace,
    tgt.tbl_tablespace_path,
    -- total size incl. indexes, toast
    pg_size_pretty(sz.tbl_total_size_bytes) as tbl_total_size,
    -- heap only (no indexes, no toast)
    pg_size_pretty(sz.tbl_size_bytes) as tbl_size,
    -- indexes size
    pg_size_pretty(sz.tbl_idx_size_bytes) as tbl_idx_size,
    st.n_live_tup,
    st.n_dead_tup,
    -- dead rows as % of all estimated rows
    case
        when st.n_live_tup + st.n_dead_tup > 0
        then round((st.n_dead_tup::numeric / (st.n_live_tup + st.n_dead_tup) * 100), 2)
        else 0
    end as dead_pct
from
    target_table tgt
    left join sizes sz on sz.tbl_oid = tgt.tbl_oid
    left join user_stats st on st.tbl_oid = tgt.tbl_oid
order by
    sz.tbl_total_size_bytes desc
;