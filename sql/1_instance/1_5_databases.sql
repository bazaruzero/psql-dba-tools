-- databases

select
    d.datname as "database",
    pg_catalog.pg_get_userbyid(d.datdba) as "owner",
    pg_catalog.pg_encoding_to_char(d.encoding) as "encoding",
    d.datcollate as "collate",
    d.datctype as "ctype",
    d.daticulocale as "icu locale",
    case 
        d.datlocprovider 
            when 'c' then 'libc' 
            when 'i' then 'icu'
    end as "locale provider",
    case
        when pg_catalog.has_database_privilege(d.datname, 'CONNECT') then pg_catalog.pg_size_pretty(pg_catalog.pg_database_size(d.datname))
        else 'No Access'
    end as "size",
    t.spcname as "tablespace"
from
    pg_catalog.pg_database d
    join pg_catalog.pg_tablespace t on d.dattablespace = t.oid
order by
    d.datname;