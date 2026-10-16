-- orphaned large objects (NOTE: generates query to run)

-- ref. to https://www.percona.com/blog/how-to-remove-an-orphan-large-object-in-postgresql-with-vacuumlo/

with t as (
    select distinct
        attrelid::regclass::varchar as table_name,
        attname                     as column_name,
        atttypid::regtype           as type
    from pg_attribute a
    join pg_class c on a.attrelid = c.oid
    where a.attnum > 0
      and not a.attisdropped
      and a.attrelid = c.oid
      and a.atttypid::regtype::varchar in ('oid', 'lo')
      and c.relkind in ('r', 'm')
      and c.relnamespace::regnamespace::varchar !~ '^pg_'
    --limit 10
),
t2 as (
    select string_agg(
        distinct 'SELECT distinct ' || column_name || ' from ' || table_name,
        ' UNION '
    ) as v_sql
    from t
)
select ' select distinct loid from pg_largeobject EXCEPT (' || v_sql || ');' as sql
from t2;