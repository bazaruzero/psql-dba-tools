-- unlogged tables

with target_tables as (
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
        end as tbl_tablespace_path,
        (select count(*) from pg_index pi where pi.indrelid = c.oid) as idx_count
    from
        pg_class c
    where
        c.relkind = 'r'
        and c.relpersistence = 'u'
        and c.relnamespace <> 'pg_catalog'::regnamespace
),
sizes as (
    select
        tgt.tbl_oid,
        pg_total_relation_size(tgt.tbl_oid) as tbl_total_size_bytes,
        pg_relation_size(tgt.tbl_oid) as tbl_size_bytes,
        pg_indexes_size(tgt.tbl_oid) as tbl_idx_size_bytes,
        coalesce(
            case
                when c.reltoastrelid <> 0 then pg_total_relation_size(c.reltoastrelid) - pg_indexes_size(c.reltoastrelid)
                else 0
            end, 0
        )::bigint as tbl_toast_size_bytes
    from
        target_tables tgt
        join pg_class c on c.oid = tgt.tbl_oid
)
select
    tgt.tbl_schema,
    tgt.tbl_name,
    tgt.tbl_tablespace,
    tgt.tbl_tablespace_path,
    tgt.idx_count,
    -- total size incl. indexes, toast
    pg_size_pretty(sz.tbl_total_size_bytes) as tbl_total_size,
    -- heap only (no indexes, no toast)
    pg_size_pretty(sz.tbl_size_bytes) as tbl_size,
    -- indexes size
    pg_size_pretty(sz.tbl_idx_size_bytes) as tbl_idx_size,
    -- toast data size
    pg_size_pretty(sz.tbl_toast_size_bytes) as tbl_toast_size
from
    target_tables tgt
    left join sizes sz on sz.tbl_oid = tgt.tbl_oid
order by
    sz.tbl_total_size_bytes desc
;