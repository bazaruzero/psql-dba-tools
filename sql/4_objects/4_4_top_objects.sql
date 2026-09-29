-- top objects

with object_sizes as (
    select
        c.relnamespace::regnamespace::text as obj_schema,
        case c.relkind
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
            else c.relkind::text
        end as obj_type,
        c.relname as obj_name,
        coalesce(pg_total_relation_size(c.oid), 0) as obj_size_bytes
    from
        pg_class c
),
schema_totals as (
    select
        obj_schema,
        sum(obj_size_bytes) as obj_schema_size_bytes
    from
        object_sizes
    group by
        obj_schema
),
db_total as (
    select
        pg_database_size(current_database()) as db_size_bytes
)
select
    o.obj_schema,
    o.obj_type,
    o.obj_name,
    pg_size_pretty(o.obj_size_bytes) as obj_size,
    round(100.0 * o.obj_size_bytes / nullif(st.obj_schema_size_bytes, 0), 2) as obj_schema_ratio,
    pg_size_pretty(st.obj_schema_size_bytes) as schema_size,
    round(100.0 * o.obj_size_bytes / nullif(dt.db_size_bytes, 0), 2) as obj_db_ratio,
    pg_size_pretty(dt.db_size_bytes) as db_size
from
    object_sizes o
    join schema_totals st on o.obj_schema = st.obj_schema
    cross join db_total dt
order by
    o.obj_size_bytes desc
limit 10;