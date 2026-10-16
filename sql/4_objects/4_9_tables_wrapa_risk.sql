-- tables with wraparound risk

\echo ''
\echo '##'
\echo '## Global freeze settings:'
\echo '##'
\echo ''

select
    name,
    setting,
    unit,
    context
    short_desc
from
    pg_settings
where
   name like '%_freeze_%';

\echo ''
\echo '##'
\echo '## Tables with wraparound risk:'
\echo '##'
\echo ''

with main_opts as (
    select
        c.oid as tbl_oid,
        c.relnamespace::regnamespace::text as tbl_schema,
        c.relname as tbl_name,
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
        end as freeze_max_age,
        c.reloptions as tbl_reloptions
    from pg_class c
    where
        c.relkind in ('r','m')
        and c.relnamespace::regnamespace::text not in ('pg_catalog','information_schema')
        --and c.relnamespace::regnamespace::text = 'myschema'
),
toast_opts as (
    select
        m.tbl_oid,
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
        main_opts m
        left join pg_class mc on mc.oid = m.tbl_oid
        left join pg_class t on t.oid = mc.reltoastrelid
),
agg as (
    select
        m.tbl_oid,
        m.tbl_schema,
        m.tbl_name,
        m.tbl_reloptions,
        round(
            100.0 * m.xid_age::numeric
                / nullif(
                    coalesce(m.freeze_table_age,
                             current_setting('vacuum_freeze_table_age')::bigint),
                    0
                  ),
            2
        ) as main_pct_aggressive_vacuum,
        round(
            100.0 * m.xid_age::numeric
                / nullif(
                    coalesce(m.freeze_max_age,
                             current_setting('autovacuum_freeze_max_age')::bigint),
                    0
                  ),
            2
        ) as main_pct_wraparound_vacuum,
        coalesce(round(
            100.0 * t.xid_age::numeric
                / nullif(
                    coalesce(t.freeze_table_age,
                             current_setting('vacuum_freeze_table_age')::bigint),
                    0
                  ),
            2
        ), 0) as toast_pct_aggressive_vacuum,
        coalesce(round(
            100.0 * t.xid_age::numeric
                / nullif(
                    coalesce(t.freeze_max_age,
                             current_setting('autovacuum_freeze_max_age')::bigint),
                    0
                  ),
            2
        ), 0) as toast_pct_wraparound_vacuum
    from
        main_opts m
        left join toast_opts t on t.tbl_oid = m.tbl_oid
)
select
    tbl_schema,
    tbl_name,
    greatest(main_pct_aggressive_vacuum, toast_pct_aggressive_vacuum) as pct_aggressive_vacuum,
    greatest(main_pct_wraparound_vacuum, toast_pct_wraparound_vacuum) as pct_wraparound_vacuum,
    pg_size_pretty(pg_total_relation_size(tbl_oid)) as tbl_total_size,
    tbl_reloptions as tbl_settings
from
    agg
where 1=1
    and pg_total_relation_size(tbl_oid) > 1073741824 -- 1GB
    and greatest(main_pct_wraparound_vacuum, toast_pct_wraparound_vacuum) > 10
order by
    greatest(main_pct_wraparound_vacuum, toast_pct_wraparound_vacuum) desc nulls last
limit 10;