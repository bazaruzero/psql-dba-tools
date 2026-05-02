-- schema permissions

\echo ''
\echo '--'
\echo '-- USAGE (right to use objects in the schema)'
\echo '-- CREATE (right to create objects in the schema)'
\echo '--'
\echo ''

select 
    n.nspname as schema_name,
    pg_get_userbyid(n.nspowner) as owner,
    (aclexplode(n.nspacl)).grantee::regrole as role_name,
    (aclexplode(n.nspacl)).privilege_type as privilege,
    (aclexplode(n.nspacl)).is_grantable
from 
    pg_namespace n
where
    1 = 1
    --n.nspname = 'myschema'
order by 
    schema_name, owner, role_name, privilege;