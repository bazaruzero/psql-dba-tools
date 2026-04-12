-- objects count (by type)

select
    pg_get_userbyid(c.relowner) as obj_owner,
    c.relnamespace::regnamespace::text as obj_schema,
    case
        when c.reltablespace <> 0 then (select ts.spcname from pg_tablespace ts where ts.oid = c.reltablespace)
        else (select ts.spcname from pg_database d, pg_tablespace ts where d.dattablespace = ts.oid and d.datname = current_database())
    end as obj_tbs,
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
    count(*) as obj_count,
    round(100.0 * count(*) / sum(count(*)) over (), 2) as obj_ratio,
    sum(count(*)) over () as obj_total
from
    pg_class c
group by
    obj_owner, obj_schema, obj_tbs, obj_type
order by
    obj_count desc;