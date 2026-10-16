-- tables with high index write activity 

-- candidates for bloated index detection

-- ref. to https://github.com/dataegret/pg-utils/blob/master/sql/table_index_write_activity.sql 

with idx_write_activity as (
    select
        s.schemaname as tbl_scheman,
        s.relname as tbl_name,
        case when c.relkind = 'p' then true else false end as is_partitioned,
        c.relispartition as is_partition,
        pg_relation_size(s.relid) as tbl_size_bytes,
        case
            when c.relkind = 'p' then (
                select coalesce(sum(pg_total_relation_size(pt.oid)), 0)::bigint
                from pg_partition_tree(s.relid) l
                join pg_class pt on pt.oid = l.relid
            )
            else pg_total_relation_size(s.relid)
        end as tbl_total_size_bytes,
        coalesce(
            t.spcname,
            (select spcname from pg_tablespace where oid = (select dattablespace from pg_database where datname = current_database()))
        ) as tblsp,
        s.seq_scan,
        s.idx_scan,
        s.n_tup_ins,
        s.n_tup_upd,
        s.n_tup_del,
        (coalesce(s.n_tup_ins, 0) + coalesce(s.n_tup_upd, 0) - coalesce(s.n_tup_hot_upd, 0) + coalesce(s.n_tup_del, 0)) as total,
        (coalesce(s.n_tup_hot_upd, 0)::float * 100 / (case when s.n_tup_upd > 0 then s.n_tup_upd else 1 end)::float)::numeric(10, 2) as hot_rate,
        (select v[1] from regexp_matches(c.reloptions::text, E'fillfactor=(\\d+)') as r(v) limit 1) as fillfactor
    from
        pg_stat_user_tables s
        join pg_class c on c.oid = s.relid
        left join pg_tablespace t on t.oid = c.reltablespace
    where
        coalesce(s.n_tup_ins, 0) + coalesce(s.n_tup_upd, 0) - coalesce(s.n_tup_hot_upd, 0) + coalesce(s.n_tup_del, 0) > 100
)
select
    (select stats_reset from pg_stat_database where datname = current_database()) as stats_reset,
    tbl_scheman,
    tbl_name,
    is_partitioned,
    is_partition,
    pg_size_pretty(tbl_size_bytes) as tbl_size,
    pg_size_pretty(tbl_total_size_bytes) as tbl_total_size,
    tblsp,
    seq_scan,
    idx_scan,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    total,
    hot_rate,
    fillfactor
from
    idx_write_activity
order by
    total desc
limit 50;