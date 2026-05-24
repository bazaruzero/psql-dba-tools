-- cluster size

select
    datname,
    pg_size_pretty(pg_database_size(datname)) as size,
    round(100.0 * pg_database_size(datname) / sum(pg_database_size(datname)) over (), 2) as pct
from
    pg_database
--where
--    datistemplate = false
--    AND datallowconn = true

union all

select
    'TOTAL',
    pg_size_pretty(sum(pg_database_size(datname))),
    100.0
from
    pg_database
--where
--    datistemplate = false
--    and datallowconn = true
ORDER BY
    pct;