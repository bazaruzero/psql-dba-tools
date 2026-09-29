-- top owners

with owner_sizes as (
    select
        pg_get_userbyid(c.relowner) as obj_owner,
        sum(pg_relation_size(c.oid)) as obj_size,
        count(*) as obj_count
    from
        pg_class c
    group by
        obj_owner
),
db_size as (
    select
        pg_database_size(current_database()) as db_size,
        (select count(*) from pg_class) as db_obj_count
)
select
    os.obj_owner,
    pg_size_pretty(os.obj_size) as obj_size,
    round(100.0 * os.obj_size / ds.db_size, 2) as obj_size_ratio,
    pg_size_pretty(ds.db_size) as db_size,
    os.obj_count,
    round(100.0 * os.obj_count / ds.db_obj_count, 2) as obj_count_ratio,
    ds.db_obj_count
from
    owner_sizes os,
    db_size ds
order by
    os.obj_size desc;