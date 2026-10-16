-- tables with strange FK

-- fk column type differs from referenced column type

-- ref. to https://github.com/dataegret/pg-utils/blob/master/sql/check_strange_fk.sql

with fk_constraints as (
    select
        pc.oid as con_oid,
        pc.conname as fk_name,
        pc.conrelid as tbl_oid,
        pc.confrelid as ref_tbl_oid,
        pc.conkey[1] as fk_attnum,
        pc.confkey[1] as ref_attnum,
        pc.conrelid::regnamespace::text as tbl_schema
    from
        pg_constraint pc
    where
        pc.contype = 'f'
        and pc.conrelid::regnamespace::text not like 'pg\_%'
        and pc.conrelid::regnamespace::text <> 'information_schema'
        --and pc.conrelid::regnamespace::text = 'myschema'
)
select
    fc.tbl_oid::regclass::text || '.' || pa1.attname as fk_col,
    pt1.typname as fk_col_type,
    fc.ref_tbl_oid::regclass::text || '.' || pa2.attname as ref_col,
    pt2.typname as ref_col_type
from
    fk_constraints fc
    join pg_attribute pa1
        on pa1.attrelid = fc.tbl_oid
        and pa1.attnum = fc.fk_attnum
    join pg_attribute pa2
        on pa2.attrelid = fc.ref_tbl_oid
        and pa2.attnum = fc.ref_attnum
    join pg_type pt1 on pt1.oid = pa1.atttypid
    join pg_type pt2 on pt2.oid = pa2.atttypid
where
    pa1.atttypid <> pa2.atttypid
order by
    fc.tbl_schema,
    fc.tbl_oid::regclass::text,
    pa1.attname;