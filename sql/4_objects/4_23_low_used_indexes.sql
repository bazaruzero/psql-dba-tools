-- low used indexes (scan-to-write ratio below 1%)

-- ref. to https://github.com/dataegret/pg-utils/blob/master/sql/low_used_indexes.sql

with index_data as (
    select
        c.relnamespace::regnamespace::text as idx_schema,
        t.relname as idx_table,
        c.relname as idx_name,
        am.amname as idx_type,
        case c.relkind
            when 'i' then 'local'
            when 'I' then 'partitioned'
            when 'G' then 'global'
            else c.relkind::text
        end as idx_kind,
        s.idx_scan,
        s.idx_scan::float / (wt.write_activity + 1)::float as scan_write_ratio,
        wt.write_activity,
        wt.seq_scan,
        wt.n_live_tup,
        pg_relation_size(s.indexrelid) as idx_size_bytes
    from
        pg_stat_user_indexes s
        join pg_index i on i.indexrelid = s.indexrelid
        join pg_class c on c.oid = s.indexrelid
        join pg_class t on t.oid = i.indrelid
        join pg_am am on am.oid = c.relam
        join (
            select
                st.relid,
                st.seq_scan,
                st.n_live_tup,
                (coalesce(st.n_tup_ins, 0)
                 + coalesce(st.n_tup_upd, 0)
                 - coalesce(st.n_tup_hot_upd, 0)
                 + coalesce(st.n_tup_del, 0)) as write_activity
            from pg_stat_user_tables st
        ) wt on wt.relid = s.relid
    where
        not i.indisunique
        and wt.write_activity > case when pg_is_in_recovery() then -1 else 10000 end
        and s.idx_scan::float / (wt.write_activity + 1)::float < 0.01
)
select
    (select stats_reset from pg_stat_database where datname = current_database()) as stats_reset,
    idx_schema,
    idx_table,
    idx_name,
    idx_type,
    idx_kind,
    idx_scan,
    round((scan_write_ratio * 100)::numeric, 2) as scan_write_ratio_pct,
    write_activity,
    seq_scan,
    n_live_tup,
    pg_size_pretty(idx_size_bytes) as idx_size
from
    index_data
order by
    write_activity desc,
    idx_schema,
    idx_name
;