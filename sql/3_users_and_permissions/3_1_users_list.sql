-- user list

with user_info as (
    select
        r.rolname as username,
        string_agg(attr, E'\n') as attributes,
        (
            select coalesce(string_agg(m.rolname, E'\n'), 'none')
            from pg_auth_members am
            join pg_roles m on m.oid = am.roleid
            where am.member = r.oid
        ) as member_of,
        (
            select coalesce(string_agg(config_item, E'\n'), 'none')
            from unnest(r.rolconfig) as config_item
            where r.rolconfig is not null
        ) as settings
    from pg_roles r
    left join lateral unnest(
        array_remove(
            array[
                case when r.rolcanlogin = false then 'no login' else null end,
                case when r.rolinherit = false then 'no inheritance' else null end,
                case when r.rolsuper then 'superuser' else null end,
                case when r.rolcreaterole then 'create role' else null end,
                case when r.rolcreatedb then 'create db' else null end,
                case when r.rolreplication then 'replication' else null end,
                case when r.rolbypassrls then 'bypass rls' else null end,
                case when r.rolconnlimit is not null and r.rolconnlimit >= 0
                     then format('connection limit: %s', r.rolconnlimit)
                     else null end,
                case when r.rolvaliduntil is not null
                     then format('valid until: %s', r.rolvaliduntil::date)
                     else null end
            ],
            null
        )
    ) as attr on true
    group by r.rolname, r.oid, r.rolconfig
)
select
    *
from
    user_info
where
    1 = 1
    --and username = 'postgres'
    --and attributes like '%superuser%'
    --and attributes not like '%no login%' -- users
    --and attributes like '%no login%' -- groups
    --and member_of like '%mygroup%'
    --and member_of ~ 'mygroup1|mygroup2'
    --and settings != 'none'
    --and settings like '%search_path%'
order by
    username;