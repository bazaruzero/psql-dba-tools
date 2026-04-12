-- schema size

with schema_sizes as (
    select
        n.nspname as sch_name,
        sum(pg_relation_size(c.oid)) as sch_size
    from
        pg_namespace n
        join pg_class c on n.oid = c.relnamespace
    group by
        sch_name
),
db_size as (
    select pg_database_size(current_database()) as db_size
)
select
    ss.sch_name,
    pg_size_pretty(ss.sch_size) as sch_size,
    round(100.0 * ss.sch_size / ds.db_size, 2) as sch_ratio,
    pg_size_pretty(ds.db_size) as db_size
from
    schema_sizes ss,
    db_size ds
order by
    ss.sch_size desc;