-- cached objects (pg_buffercache required)

with buffer_counts as (
    -- number of shared_buffers pages per relation, across all databases
    select
        reldatabase,
        relfilenode,
        count(1) as cached_pages
    from
        pg_buffercache
    group by
        reldatabase, relfilenode
),
filenode_map as (
    -- 1) relations with storage, except TOAST-related (handled separately below)
    select
        c.relfilenode as filenode,
        ns.nspname as obj_schema,
        c.relname as obj_name,
        c.relkind as obj_kind,
        c.oid as obj_oid
    from
        pg_class c
        join pg_namespace ns on ns.oid = c.relnamespace
    where
        c.relfilenode <> 0
        and c.relkind <> 't'
        and not (
            c.relkind = 'i'
            and exists (
                select 1
                from pg_index i
                join pg_class ti on ti.oid = i.indrelid
                where i.indexrelid = c.oid and ti.relkind = 't'
            )
        )
    union all
    -- 2) TOAST tables, labeled via their parent table
    select
        t.relfilenode as filenode,
        pns.nspname as obj_schema,
        p.relname || ' (toast)' as obj_name,
        't' as obj_kind,
        p.oid as obj_oid
    from
        pg_class p
        join pg_namespace pns on pns.oid = p.relnamespace
        join pg_class t on t.oid = p.reltoastrelid
    where
        t.relfilenode <> 0
    union all
    -- 3) TOAST indexes, labeled via their parent table
    select
        ti.relfilenode as filenode,
        pns.nspname as obj_schema,
        p.relname || ' (toast index)' as obj_name,
        'i' as obj_kind,
        p.oid as obj_oid
    from
        pg_class p
        join pg_namespace pns on pns.oid = p.relnamespace
        join pg_class t on t.oid = p.reltoastrelid
        join pg_index i on i.indrelid = t.oid
        join pg_class ti on ti.oid = i.indexrelid
    where
        ti.relfilenode <> 0
)
select
    coalesce(d.datname, '?') as db_name,
    coalesce(m.obj_schema, '-') as obj_schema,
    coalesce(m.obj_name, '-') as obj_name,
    case m.obj_kind
        when 'r' then 'table'
        when 'i' then 'index'
        when 'S' then 'sequence'
        when 'v' then 'view'
        when 'm' then 'materialized view'
        when 'c' then 'composite type'
        when 't' then 'toast table'
        when 'f' then 'foreign table'
        when 'p' then 'partitioned table'
        when 'I' then 'partitioned index'
        when 'G' then 'global index'
        else coalesce(m.obj_kind::text, '-')
    end as obj_type,
    -- raw identifier to look up manually when the object could not be resolved
    b.relfilenode,
    -- physical file path for manual investigation
    'base/' || b.reldatabase || '/' || b.relfilenode as relpath,
    b.cached_pages,
    -- buffered size in shared_buffers
    pg_size_pretty(b.cached_pages * 8192) as cached_size,
    -- how much of the relation itself stays in cache, in percent (current database only)
    case
        when m.obj_oid is not null and pg_table_size(m.obj_oid) > 0
        then round(100.0 * b.cached_pages * 8192 / pg_table_size(m.obj_oid), 1)
        else null
    end as percent_of_relation,
    -- share of the whole shared_buffers, in percent
    round(100.0 * b.cached_pages / (select setting from pg_settings where name = 'shared_buffers')::integer, 1) as buffers_percent
from
    buffer_counts b
    -- pg_database is a global catalog, so the database name is available for every row
    left join pg_database d on d.oid = b.reldatabase
    -- the map is built from the current database's pg_class, so it only matches
    -- buffers belonging to the currently connected database
    left join filenode_map m
        on m.filenode = b.relfilenode
        and b.reldatabase = (select oid from pg_database where datname = current_database())
order by
    b.cached_pages desc
limit 30
;