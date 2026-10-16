-- tables with write activity

-- if hot_rate is low, there may be some indexes that prevent HOT updates

-- ref. to https://github.com/dataegret/pg-utils/blob/master/sql/table_write_activity.sql

select
    pg_stat_all_tables.schemaname || '.' || pg_stat_all_tables.relname as table_name,
    pg_size_pretty(pg_relation_size(relid)) as table_size,
    coalesce(
        t.spcname,
        (select spcname
         from pg_tablespace
         where oid = (select dattablespace
                      from pg_database
                      where datname = current_database())) )as tablespace,
    seq_scan,
    idx_scan,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    coalesce(n_tup_ins, 0) + 2 * coalesce(n_tup_upd, 0) - coalesce(n_tup_hot_upd, 0) + coalesce(n_tup_del, 0) as total,
    (coalesce(n_tup_hot_upd, 0)::float * 100 / (case when n_tup_upd > 0 then n_tup_upd else 1 end)::float)::numeric(10, 2) as hot_rate,
    (select v[1]
     from regexp_matches(reloptions::text, e'fillfactor=(\\d+)') as r(v)
     limit 1) as fillfactor
from pg_stat_all_tables
join pg_class c on c.oid = relid
left join pg_tablespace t on t.oid = c.reltablespace
where 1=1
    and (coalesce(n_tup_ins, 0) + coalesce(n_tup_upd, 0) + coalesce(n_tup_del, 0)) > 0
    and pg_stat_all_tables.schemaname not in ('pg_catalog', 'pg_global')
order by total desc
limit 50;