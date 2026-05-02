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
    from (
        select
            rolname,
            unnest(
                array_remove(
                    array[
                        case when rolcanlogin = false then 'no login' else null end,
                        case when rolinherit = false then 'no inheritance' else null end,
                        case when rolsuper then 'superuser' else null end,
                        case when rolcreaterole then 'create role' else null end,
                        case when rolcreatedb then 'create db' else null end,
                        case when rolreplication then 'replication' else null end,
                        case when rolbypassrls then 'bypass rls' else null end,
                        case when rolconnlimit is not null and rolconnlimit >= 0 
                             then format('connection limit: %s', rolconnlimit) 
                             else null end,
                        case when rolvaliduntil is not null 
                             then format('valid until: %s', rolvaliduntil::date) 
                             else null end
                    ],
                    null
                )
            ) as attr
        from pg_roles
    ) t
    join pg_roles r on r.rolname = t.rolname
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