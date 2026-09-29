-- top object types

with object_types as (
    select
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
        sum(pg_relation_size(c.oid)) as obj_size,
        count(*) as obj_count
    from
        pg_class c
    group by
        obj_type
),
db_size as (
    select
        pg_database_size(current_database()) as db_size,
        (select count(*) from pg_class) as db_obj_count
)
select
    ot.obj_type,
    pg_size_pretty(ot.obj_size) as obj_size,
    round(100.0 * ot.obj_size / ds.db_size, 2) as obj_size_ratio,
    pg_size_pretty(ds.db_size) as db_size,
    ot.obj_count,
    round(100.0 * ot.obj_count / ds.db_obj_count, 2) as obj_count_ratio,
    ds.db_obj_count
from
    object_types ot,
    db_size ds
order by
    ot.obj_size desc;