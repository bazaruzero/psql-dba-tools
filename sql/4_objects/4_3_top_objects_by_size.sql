-- top-10 objects in database by total size (pg_total_relation_size)

with db_size as (
    select pg_database_size(current_database()) as total_db_size
),
object_size as (
    select
        c.relnamespace::regnamespace::text as obj_schema,
        c.relname as obj_name,
        case c.relkind
            when 'r' then 'table'
            when 'p' then 'partitioned_table'
            when 'i' then 'index'
            when 'I' then 'partitioned_index'
            when 'G' then 'global_index'
            when 'S' then 'sequence'
            when 'v' then 'view'
            when 'm' then 'materialized_view'
            when 'f' then 'foreign_table'
            when 'c' then 'composite_type'
            else other_relkind
        end as obj_type,
        pg_total_relation_size(c.oid) as obj_size,
        pg_size_pretty(pg_total_relation_size(c.oid)) as obj_size_pretty
    from
        pg_class c
        left join pg_namespace n on n.oid = c.relnamespace
        cross join lateral (select case when c.relkind not in ('r','p','i','I','G','S','v','m','f','c') then c.relkind::text else null end as other_relkind) sub
    where
        n.nspname not in ('pg_catalog', 'information_schema')
        and c.relkind in ('r','p','i','I','G','S','v','m','f','c')
),
result as (
    select
        os.*,
        d.total_db_size,
        round(100.0 * os.obj_size / nullif(d.total_db_size, 0), 2) as obj_db_size_pct,
        round(100.0 * os.obj_size / nullif(sum(os.obj_size) over (partition by os.obj_schema), 0), 2) as obj_sch_size_pct
    from
        object_size os
        cross join db_size d
)
select
    obj_schema,
    obj_name,
    obj_type,
    obj_size_pretty as obj_size_human,
    obj_size,
    obj_db_size_pct,
    obj_sch_size_pct
from
    result
order by
    obj_size desc
limit 10
--\gx