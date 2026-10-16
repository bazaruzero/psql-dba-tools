-- user tables with reference to large objects

-- ref. to https://www.percona.com/blog/how-to-remove-an-orphan-large-object-in-postgresql-with-vacuumlo/

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
;