-- tables without indexed FK

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
fk_constraints as (
    select
        pc.oid as con_oid,
        pc.conname as fk_name,
        pc.conrelid as tbl_oid,
        pc.conkey as fk_attnums
    from
        pg_constraint pc
    where
        pc.contype = 'f'
),
tbl_indexes as (
    select
        pi.indrelid as tbl_oid,
        pi.indexrelid as idx_oid,
        pi.indkey::int2[] as idx_attnums
    from
        pg_index pi
)
select
    ct.tbl_schema,
    ct.tbl_name,
    fc.fk_name,
    (
        select string_agg(a.attname, ', ' order by ck.ord)
        from unnest(fc.fk_attnums) with ordinality ck(attnum, ord)
        join pg_attribute a
            on a.attrelid = fc.tbl_oid
            and a.attnum = ck.attnum
    ) as fk_cols,
    ct.is_partitioned,
    ct.is_partition,
    pg_size_pretty(ct.tbl_total_size_bytes) as tbl_total_size
from
    candidate_tables ct
    join fk_constraints fc on fc.tbl_oid = ct.tbl_oid
where
    not exists (
        select 1
        from tbl_indexes ti
        where
            ti.tbl_oid = fc.tbl_oid
            and (
                select array_agg(k order by ord)
                from unnest(ti.idx_attnums) with ordinality u(k, ord)
                where ord <= array_length(fc.fk_attnums, 1)
            ) = fc.fk_attnums
    )
order by
    ct.tbl_total_size_bytes desc nulls last;