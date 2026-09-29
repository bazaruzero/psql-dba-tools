-- table info detailed (adjust filter inside "target_table" CTE)

\echo ''
\echo '##'
\echo '## NOTE: uncomment "c.relnamespace::regnamespace::text =" line in "target_table" CTE'
\echo '##       to additionally restrict by schema. Table name filter is required.'
\echo '##'
\echo ''

with db_size as (
    select pg_database_size(current_database()) as total_db_size
),
target_table as (
    select
        c.oid as tbl_oid,
        c.relnamespace::regnamespace::text as table_schema,
        c.relname as table_name,
        c.relkind,
        c.relispartition,
        c.reloptions,
        c.reltablespace,
        case
            when c.reltablespace <> 0 then (select ts.spcname from pg_tablespace ts where ts.oid = c.reltablespace)
            else (select ts.spcname from pg_database d, pg_tablespace ts where d.datname = current_database() and d.dattablespace = ts.oid)
        end as tablespace,
        case
            when c.reltablespace <> 0 then pg_tablespace_location(c.reltablespace)
            else (select pg_tablespace_location(d.dattablespace) from pg_database d where d.datname = current_database())
        end as tablespace_path
    from pg_class c
    where
        c.relkind in ('r','p')
        --and c.relnamespace::regnamespace::text = 'myschema'
        and c.relname = 'mytable'
),
subtree_nodes as (
    select
        tt.tbl_oid as root_oid,
        true as is_root,
        cc.*
    from target_table tt
    join pg_class cc on cc.oid = tt.tbl_oid
    union all
    select
        tt.tbl_oid as root_oid,
        false as is_root,
        cc.*
    from target_table tt
    cross join lateral pg_partition_tree(tt.tbl_oid) pt
    join pg_class cc on cc.oid = pt.relid
    where
        tt.relkind = 'p'
        and cc.oid <> tt.tbl_oid
),
subtree_sizes as (
    select
        sn.root_oid as tbl_oid,
        coalesce(sum(pg_total_relation_size(sn.oid)), 0)::bigint as tbl_total_size_bytes,
        coalesce(sum(
            case
                when sn.reltoastrelid = 0 then pg_total_relation_size(sn.oid) - pg_indexes_size(sn.oid)
                else pg_total_relation_size(sn.oid) - pg_indexes_size(sn.oid) - pg_total_relation_size(sn.reltoastrelid)
            end
        ), 0)::bigint as tbl_size_bytes,
        coalesce(sum(
            case
                when not sn.is_root then pg_relation_size(sn.oid)
                else 0
            end
        ), 0)::bigint as tbl_part_size_bytes,
        coalesce(sum(pg_indexes_size(sn.oid)), 0)::bigint as tbl_idx_size_bytes,
        coalesce(sum(
            case
                when sn.reltoastrelid <> 0 then pg_total_relation_size(sn.reltoastrelid) - pg_indexes_size(sn.reltoastrelid)
                else 0
            end
        ), 0)::bigint as tbl_toast_size_bytes,
        coalesce(sum(
            case
                when sn.reltoastrelid <> 0 then pg_indexes_size(sn.reltoastrelid)
                else 0
            end
        ), 0)::bigint as tbl_toast_idx_size_bytes
    from subtree_nodes sn
    group by sn.root_oid
),
part_metadata as (
    select
        c.oid as tbl_oid,
        case when c.relkind = 'p' then true else false end as is_partitioned,
        c.relispartition as is_partition,
        case
            when c.relispartition = 'f' and c.relkind = 'p' then 'root'
            when c.relispartition = 't' and c.relkind = 'p' then 'sub'
            when c.relispartition = 't' and c.relkind = 'r' then 'leaf'
            when c.relispartition = 'f' and c.relkind = 'r' then '-'
        end as partition_level,
        case
            when c.relispartition = 'f' and (c.relkind = 'r' or c.relkind = 'p') then '-'
            else pg_get_partition_constraintdef(c.oid)::text
        end as partition_bound,
        case
            when (c.relispartition = 'f' or c.relispartition = 't') and c.relkind = 'r' then '-'
            else pg_get_partkeydef(c.oid)
        end as partition_key,
        case
            when (c.relispartition = 'f' or c.relispartition = 't') and c.relkind = 'p' then
                (select count(*) from pg_partition_tree(c.oid) pt where pt.level <> 0)
            else 0
        end as partition_count
    from pg_class c
),
scope_lookup as (
    with recursive walk as (
        select
            tt.tbl_oid as original_oid,
            cc.oid as cur_oid,
            0 as depth
        from target_table tt
        join pg_class cc on cc.oid = tt.tbl_oid
        union all
        select
            w.original_oid,
            inh.inhparent,
            w.depth + 1
        from walk w
        join pg_inherits inh on inh.inhrelid = w.cur_oid
    )
    select distinct on (original_oid)
        original_oid as tbl_oid,
        cur_oid as scope_oid
    from walk
    order by original_oid, depth desc
),
index_counts as (
    select
        sl.tbl_oid,
        coalesce(sub.idx_local_count, 0) as idx_local_count,
        coalesce(sub.idx_global_count, 0) as idx_global_count
    from scope_lookup sl
    left join lateral (
        with descendants as (
            select sl.scope_oid as rid
            union
            select pt.relid as rid
            from pg_partition_tree(sl.scope_oid) pt
            where pt.relid <> sl.scope_oid
        )
        select
            count(*) filter (where ic.relkind = 'i') as idx_local_count,
            count(*) filter (where ic.relkind = 'G') as idx_global_count
        from descendants ds
        join pg_index i on i.indrelid = ds.rid
        join pg_class ic on ic.oid = i.indexrelid
        where ic.relkind in ('i', 'G')
    ) sub on true
),
main_freeze_opts as (
    select
        m.tbl_oid,
        age(c.relfrozenxid) as xid_age,
        case when c.reloptions is null then null
             else (
                 select split_part(opt, '=', 2)::bigint
                 from unnest(c.reloptions) opt
                 where split_part(opt, '=', 1) = 'autovacuum_freeze_table_age'
                 limit 1
             )
        end as freeze_table_age,
        case when c.reloptions is null then null
             else (
                 select split_part(opt, '=', 2)::bigint
                 from unnest(c.reloptions) opt
                 where split_part(opt, '=', 1) = 'autovacuum_freeze_max_age'
                 limit 1
             )
        end as freeze_max_age
    from
        target_table m
        join pg_class c on c.oid = m.tbl_oid
),
toast_freeze_opts as (
    select
        mf.tbl_oid,
        case when t.oid is not null then age(t.relfrozenxid) end as xid_age,
        case when t.oid is null or t.reloptions is null then null
             else (
                 select split_part(opt, '=', 2)::bigint
                 from unnest(t.reloptions) opt
                 where split_part(opt, '=', 1) = 'toast.autovacuum_freeze_table_age'
                 limit 1
             )
        end as freeze_table_age,
        case when t.oid is null or t.reloptions is null then null
             else (
                 select split_part(opt, '=', 2)::bigint
                 from unnest(t.reloptions) opt
                 where split_part(opt, '=', 1) = 'toast.autovacuum_freeze_max_age'
                 limit 1
             )
        end as freeze_max_age
    from
        main_freeze_opts mf
        join pg_class mc on mc.oid = mf.tbl_oid
        left join pg_class t on t.oid = mc.reltoastrelid
),
freeze_metrics as (
    select
        mf.tbl_oid,
        round(
            100.0 * mf.xid_age::numeric
                / nullif(
                    coalesce(mf.freeze_table_age,
                             current_setting('vacuum_freeze_table_age')::bigint),
                    0
                  ),
            2
        ) as main_pct_aggressive_vacuum,
        round(
            100.0 * mf.xid_age::numeric
                / nullif(
                    coalesce(mf.freeze_max_age,
                             current_setting('autovacuum_freeze_max_age')::bigint),
                    0
                  ),
            2
        ) as main_pct_wraparound_vacuum,
        coalesce(round(
            100.0 * tf.xid_age::numeric
                / nullif(
                    coalesce(tf.freeze_table_age,
                             current_setting('vacuum_freeze_table_age')::bigint),
                    0
                  ),
            2
        ), 0) as toast_pct_aggressive_vacuum,
        coalesce(round(
            100.0 * tf.xid_age::numeric
                / nullif(
                    coalesce(tf.freeze_max_age,
                             current_setting('autovacuum_freeze_max_age')::bigint),
                    0
                  ),
            2
        ), 0) as toast_pct_wraparound_vacuum
    from
        main_freeze_opts mf
        left join toast_freeze_opts tf on tf.tbl_oid = mf.tbl_oid
),
user_stats as (
    select
        s.relid as tbl_oid,
        s.n_live_tup,
        s.n_dead_tup,
        s.last_vacuum,
        s.last_analyze,
        s.last_autovacuum,
        s.last_autoanalyze
    from pg_stat_user_tables s
)
select
    tgt.table_schema as tbl_schema,
    tgt.table_name as tbl_name,
    tgt.tablespace tbl_tablespace,
    tgt.tablespace_path as tbl_tablespace_path,
    pm.is_partitioned,
    pm.is_partition,
    pm.partition_level,
    pm.partition_bound,
    pm.partition_key,
    pm.partition_count,
    pg_size_pretty(ss.tbl_total_size_bytes) as tbl_total_size,
    pg_size_pretty(ss.tbl_size_bytes) as tbl_size,
    pg_size_pretty(ss.tbl_part_size_bytes) as tbl_part_size,
    pg_size_pretty(ss.tbl_idx_size_bytes) as tbl_idx_size,
    pg_size_pretty(ss.tbl_toast_size_bytes) as tbl_toast_size,
    pg_size_pretty(ss.tbl_toast_idx_size_bytes) as tbl_toast_idx_size,
    ic.idx_local_count,
    ic.idx_global_count,
    round(100.0 * ss.tbl_total_size_bytes / nullif(d.total_db_size, 0), 2) as db_size_pct,
    pg_size_pretty(d.total_db_size) as db_size,
    us.n_live_tup,
    us.n_dead_tup,
    case
        when us.n_live_tup + us.n_dead_tup > 0
        then round((us.n_dead_tup::numeric / (us.n_live_tup + us.n_dead_tup) * 100), 2)
        else 0
    end as dead_pct,
    greatest(fm.main_pct_aggressive_vacuum, fm.toast_pct_aggressive_vacuum) as pct_aggressive_vacuum,
    greatest(fm.main_pct_wraparound_vacuum, fm.toast_pct_wraparound_vacuum) as pct_wraparound_vacuum,
    us.last_vacuum,
    us.last_analyze,
    us.last_autovacuum,
    us.last_autoanalyze,
    tgt.reloptions as table_settings
from
    target_table tgt
    left join subtree_sizes ss on ss.tbl_oid = tgt.tbl_oid
    left join part_metadata pm on pm.tbl_oid = tgt.tbl_oid
    left join index_counts ic on ic.tbl_oid = tgt.tbl_oid
    left join freeze_metrics fm on fm.tbl_oid = tgt.tbl_oid
    left join user_stats us on us.tbl_oid = tgt.tbl_oid
    cross join db_size d
\gx