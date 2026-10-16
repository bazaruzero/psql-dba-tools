-- large objects count by owner (NOTE: long running query on huge large object tables)

with lo_groups as (
    select
        lomowner as owner_oid,
        coalesce(lomacl, '{}'::aclitem[]) as lo_acl,
        count(*) as lo_count
    from
        pg_catalog.pg_largeobject_metadata
    group by
        lomowner, lomacl
)
select
    (select rolname from pg_roles where oid = g.owner_oid) as owner,
    g.lo_acl,
    g.lo_count
from
    lo_groups g
order by
    g.lo_count desc
;