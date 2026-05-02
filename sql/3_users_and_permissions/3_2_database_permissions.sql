-- database permissions

\echo ''
\echo '--'
\echo '-- Explanation of letters in the datacl field:'
\echo '-- = (empty grantee) - PUBLIC (all users)'
\echo '-- C - CREATE (right to create schemas in the database)'
\echo '-- T - TEMP (right to create temporary tables)'
\echo '-- c - CONNECT (right to connect to the database)'
\echo '-- / - separator, after which the grantor (who granted the privilege) is specified'
\echo '--'
\echo '-- Example: "app_admin=CTc/app_admin" means:'
\echo '--   role app_admin has privileges C (CREATE), T (TEMP), c (CONNECT)'
\echo '--   privileges granted by role app_admin'
\echo '--'
\echo ''

select 
    datname as database,
    array_to_string(datacl, E'\n') as access
from
    pg_database
where
    1 = 1
    --datacl is not null
order by
    datname;