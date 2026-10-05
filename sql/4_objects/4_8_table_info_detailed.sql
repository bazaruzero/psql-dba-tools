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
            when c.reltablespace <> 0 then
                coalesce(
                    nullif(pg_tablespace_location(c.reltablespace), ''),
                    current_setting('data_directory') || '/base'
                )
            else (
                select
                    coalesce(
                        nullif(pg_tablespace_location(d.dattablespace), ''),
                        current_setting('data_directory') || '/base'
                    )
                from pg_database d
                where d.datname = current_database()
            )
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
        ), 0) as toast_pct_wraparound_vacuum,
        case
            when mf.xid_age >= coalesce(mf.freeze_table_age,
                                        current_setting('vacuum_freeze_table_age')::bigint)
              or coalesce(tf.xid_age, 0) >= coalesce(tf.freeze_table_age,
                                                     current_setting('vacuum_freeze_table_age')::bigint)
            then 'aggressive'
            else 'soft'
        end as est_freeze_mode
    from
        main_freeze_opts mf
        left join toast_freeze_opts tf on tf.tbl_oid = mf.tbl_oid
),
vacuum_trigger_metrics as (
    select
        tt.tbl_oid,
        round(
            100.0 * us.n_dead_tup::numeric
                / nullif(
                    coalesce(
                        (
                            select split_part(opt, '=', 2)::bigint
                            from unnest(c.reloptions) opt
                            where split_part(opt, '=', 1) = 'autovacuum_vacuum_threshold'
                            limit 1
                        ),
                        current_setting('autovacuum_vacuum_threshold')::bigint
                    )::numeric
                    + coalesce(
                        (
                            select split_part(opt, '=', 2)::numeric
                            from unnest(c.reloptions) opt
                            where split_part(opt, '=', 1) = 'autovacuum_vacuum_scale_factor'
                            limit 1
                        ),
                        current_setting('autovacuum_vacuum_scale_factor')::numeric
                    ) * c.reltuples::numeric,
                    0
                ),
            2
        ) as pct_avacuum_dead,
        round(
            100.0 * us.n_ins_since_vacuum::numeric
                / nullif(
                    coalesce(
                        (
                            select split_part(opt, '=', 2)::bigint
                            from unnest(c.reloptions) opt
                            where split_part(opt, '=', 1) = 'autovacuum_vacuum_insert_threshold'
                            limit 1
                        ),
                        current_setting('autovacuum_vacuum_insert_threshold')::bigint
                    )::numeric
                    + coalesce(
                        (
                            select split_part(opt, '=', 2)::numeric
                            from unnest(c.reloptions) opt
                            where split_part(opt, '=', 1) = 'autovacuum_vacuum_insert_scale_factor'
                            limit 1
                        ),
                        current_setting('autovacuum_vacuum_insert_scale_factor')::numeric
                    ) * c.reltuples::numeric,
                    0
                ),
            2
        ) as pct_avacuum_insert,
        case
            when src.timeout_on and src.timeout_tbl is not null
            then round(
                    100.0 * src.elapsed_min::numeric
                        / nullif(src.timeout_tbl, 0),
                    2
                 )
            else null
        end as pct_avacuum_timeout,
        case
            when src.timeout_on and src.analyze_timeout_tbl is not null
            then round(
                    100.0 * src.analyze_elapsed_min::numeric
                        / nullif(src.analyze_timeout_tbl, 0),
                    2
                 )
            else null
        end as pct_aanalyze_timeout
    from
        target_table tt
        join pg_class c on c.oid = tt.tbl_oid
        left join pg_stat_user_tables us on us.relid = tt.tbl_oid
        cross join lateral (
            select
                coalesce(current_setting('autovacuum_timeout_threshold_enable', true), '')
                    in ('true', 't', 'on', 'yes', '1') as timeout_on,
                (
                    select split_part(opt, '=', 2)::numeric
                    from unnest(c.reloptions) opt
                    where split_part(opt, '=', 1) = 'autovacuum_vacuum_timeout'
                    limit 1
                ) as timeout_tbl,
                extract(epoch from (now() - coalesce(greatest(us.last_vacuum, us.last_autovacuum), pg_postmaster_start_time()))) / 60.0 as elapsed_min,
                (
                    select split_part(opt, '=', 2)::numeric
                    from unnest(c.reloptions) opt
                    where split_part(opt, '=', 1) = 'autovacuum_analyze_timeout'
                    limit 1
                ) as analyze_timeout_tbl,
                extract(epoch from (now() - coalesce(greatest(us.last_analyze, us.last_autoanalyze), pg_postmaster_start_time()))) / 60.0 as analyze_elapsed_min
        ) src
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
),
vacuum_activity as (
    select
        tt.tbl_oid,
        string_agg(
            'pid = ' || p.pid::text,
            '; '
            order by p.pid
        ) as running_info
    from
        target_table tt
        left join pg_stat_progress_vacuum p on p.relid = tt.tbl_oid
    group by tt.tbl_oid
),
analyze_activity as (
    select
        tt.tbl_oid,
        string_agg(
            'pid = ' || p.pid::text,
            '; '
            order by p.pid
        ) as running_info
    from
        target_table tt
        left join pg_stat_progress_analyze p on p.relid = tt.tbl_oid
    group by tt.tbl_oid
)
select
    tgt.table_schema as tbl_schema,
    tgt.table_name as tbl_name,
    -- tablespace name; falls back to DB default tablespace if not set
    tgt.tablespace tbl_tablespace,
    -- filesystem path of the tablespace
    tgt.tablespace_path as tbl_tablespace_path,
    -- true when the table is a partitioned (parent) table
    pm.is_partitioned,
    -- true when the table itself is a partition of some parent
    pm.is_partition,
    -- position in the partition tree: root/sub/leaf, '-' for plain tables
    pm.partition_level,
    -- partition bound (constraint definition), '-' if not applicable
    pm.partition_bound,
    -- partition key definition, '-' if not applicable
    pm.partition_key,
    -- number of partitions in the whole subtree
    pm.partition_count,
    -- total size incl. indexes and TOAST, whole subtree
    pg_size_pretty(ss.tbl_total_size_bytes) as tbl_total_size,
    -- heap only (no indexes, no TOAST), whole subtree
    pg_size_pretty(ss.tbl_size_bytes) as tbl_size,
    -- heap size of child partitions only
    pg_size_pretty(ss.tbl_part_size_bytes) as tbl_part_size,
    -- all indexes size, whole subtree
    pg_size_pretty(ss.tbl_idx_size_bytes) as tbl_idx_size,
    -- TOAST data size, whole subtree
    pg_size_pretty(ss.tbl_toast_size_bytes) as tbl_toast_size,
    -- TOAST index size, whole subtree
    pg_size_pretty(ss.tbl_toast_idx_size_bytes) as tbl_toast_idx_size,
    -- local (per-partition) indexes count across the scope
    ic.idx_local_count,
    ic.idx_global_count,
    round(100.0 * ss.tbl_total_size_bytes / nullif(d.total_db_size, 0), 2) as db_size_pct,
    pg_size_pretty(d.total_db_size) as db_size,
    us.n_live_tup,
    us.n_dead_tup,
    -- dead rows as % of all estimated rows
    case
        when us.n_live_tup + us.n_dead_tup > 0
        then round((us.n_dead_tup::numeric / (us.n_live_tup + us.n_dead_tup) * 100), 2)
        else 0
    end as dead_pct,
    -- % of freeze-table-age budget consumed (worst of main/TOAST)
    greatest(fm.main_pct_aggressive_vacuum, fm.toast_pct_aggressive_vacuum) as pct_aggressive_vacuum,
    -- % of wraparound (freeze-max-age) budget consumed (worst of main/TOAST)
    greatest(fm.main_pct_wraparound_vacuum, fm.toast_pct_wraparound_vacuum) as pct_wraparound_vacuum,
    -- % of dead-tuples autovacuum trigger consumed (threshold + scale_factor * reltuples)
    vtm.pct_avacuum_dead,
    -- % of insert-trigger autovacuum budget consumed since last vacuum
    vtm.pct_avacuum_insert,
    -- % of elapsed time vs per-table autovacuum_vacuum_timeout, '-' if feature disabled/not set
    coalesce(vtm.pct_avacuum_timeout::text, '-') as pct_avacuum_timeout,
    -- % of elapsed time vs per-table autovacuum_analyze_timeout, '-' if feature disabled/not set
    coalesce(vtm.pct_aanalyze_timeout::text, '-') as pct_aanalyze_timeout,
    -- estimated freeze mode: aggressive when freeze-table age threshold reached, otherwise soft
    fm.est_freeze_mode,
    us.last_vacuum,
    us.last_analyze,
    us.last_autovacuum,
    us.last_autoanalyze,
    tgt.reloptions as table_settings,
    case
        when va.running_info is not null then 'yes (' || va.running_info || ')'
        else 'no'
    end as is_vacuum_running,
    case
        when aa.running_info is not null then 'yes (' || aa.running_info || ')'
        else 'no'
    end as is_analyze_running
from
    target_table tgt
    left join subtree_sizes ss on ss.tbl_oid = tgt.tbl_oid
    left join part_metadata pm on pm.tbl_oid = tgt.tbl_oid
    left join index_counts ic on ic.tbl_oid = tgt.tbl_oid
    left join freeze_metrics fm on fm.tbl_oid = tgt.tbl_oid
    left join vacuum_trigger_metrics vtm on vtm.tbl_oid = tgt.tbl_oid
    left join user_stats us on us.tbl_oid = tgt.tbl_oid
    left join vacuum_activity va on va.tbl_oid = tgt.tbl_oid
    left join analyze_activity aa on aa.tbl_oid = tgt.tbl_oid
    cross join db_size d
\gx