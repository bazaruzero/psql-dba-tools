-- tables without uniq indexes

-- ref. to https://github.com/dataegret/pg-utils/blob/master/sql/check_uniq_indexes.sql

with candidate_tables as (
    select
        c.oid as tbl_oid,
        c.relnamespace::regnamespace::text as tbl_schema,
        c.relname as tbl_name,
        case when c.relkind = 'p' then true else false end as is_partitioned,
        c.relispartition as is_partition,
        pg_total_relation_size(c.oid) as tbl_total_size_bytes
    from
        pg_class c
    where
        c.relkind in ('r','p')
        and c.relnamespace::regnamespace::text not like 'pg\_%'
        and c.relnamespace::regnamespace::text <> 'information_schema'
        --and c.relnamespace::regnamespace::text = 'myschema'
),
valid_uniq_idx as (
    select
        pi.indrelid as tbl_oid,
        pi.indexrelid as idx_oid
    from
        pg_index pi
    where
        pi.indisunique = 't'
        and not exists (
            select 1
            from pg_attribute t_attr
            join pg_attribute i_attr
                on i_attr.attname = t_attr.attname
                and i_attr.attrelid = pi.indexrelid
            where
                t_attr.attrelid = pi.indrelid
                and t_attr.attnotnull <> 't'
        )
),
partition_ancestors as (
    with recursive walk as (
        select
            ct.tbl_oid as original_oid,
            ct.tbl_oid as cur_oid
        from candidate_tables ct
        where ct.is_partition
        union all
        select
            w.original_oid,
            inh.inhparent
        from walk w
        join pg_inherits inh on inh.inhrelid = w.cur_oid
    )
    select
        original_oid as tbl_oid,
        cur_oid as ancestor_oid
    from walk
)
select
    tbl_schema,
    tbl_name,
    is_partitioned,
    is_partition,
    pg_size_pretty(tbl_total_size_bytes) as tbl_total_size
from
    candidate_tables ct
where
    not exists (
        select 1
        from valid_uniq_idx vui
        where
            vui.tbl_oid = ct.tbl_oid
    )
    and not exists (
        select 1
        from partition_ancestors pa
        join valid_uniq_idx vui on vui.tbl_oid = pa.ancestor_oid
        where
            pa.tbl_oid = ct.tbl_oid
    )
order by
    tbl_total_size_bytes desc nulls last;