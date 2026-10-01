-- tables without PK

-- ref. to https://github.com/dataegret/pg-utils/blob/master/sql/check_all_tables_have_pk.sql

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
),
pk_holders as (
    select pa.tbl_oid, pa.ancestor_oid as holder_oid
    from partition_ancestors pa
    union
    select pa.tbl_oid, pi.indexrelid
    from partition_ancestors pa
    join pg_index pi on pi.indrelid = pa.ancestor_oid
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
        from pg_constraint pc
        where
            pc.conrelid = ct.tbl_oid
            and pc.contype in ('p','P')
    )
    and not exists (
        select 1
        from pk_holders h
        join pg_constraint pc on pc.conrelid = h.holder_oid
        where
            h.tbl_oid = ct.tbl_oid
            and pc.contype in ('p','P')
    )
order by
    tbl_total_size_bytes desc nulls last;