-- index stats history detailed (pg_profile required)

-- set search_path = XXX;

select
    sa.sample_time,
    --ssi.datid,
    il.schemaname as idx_schema,
    substr(il.indexrelname,1,50) as idx_name,
    --ssi.*
--/*
    ssi.idx_scan,
    --coalesce(ssi.idx_tup_read, 0) - lag(ssi.idx_tup_read) over (partition by ssi.server_id, ssi.datid, ssi.indexrelid order by sa.sample_time) as tup_read_diff,
    --coalesce(ssi.idx_tup_fetch, 0) - lag(ssi.idx_tup_fetch) over (partition by ssi.server_id, ssi.datid, ssi.indexrelid order by sa.sample_time) as tup_fetch_diff,
    ssi.idx_tup_read,
    ssi.idx_tup_fetch,
    (ssi.idx_blks_read + ssi.idx_blks_hit) as idx_blks_read,
    --,pg_size_pretty(ssi.relsize) as size,
    pg_size_pretty(ssi.relsize_diff) as size_diff
    --,pg_size_pretty(ssi.relpages_bytes) as pages_bytes,
    --,pg_size_pretty(ssi.relpages_bytes_diff) as pages_bytes_diff
--*/
from
    samples sa
    join sample_stat_indexes ssi
        on sa.sample_id = ssi.sample_id and sa.server_id = ssi.server_id
    join indexes_list il
        on il.server_id=ssi.server_id and il.datid=ssi.datid and il.indexrelid=ssi.indexrelid
where
    sa.server_id = (select server_id from servers s where s.enabled and s.server_name like (select split_part(pg_hostname(),'.',1) || '%'))
    --and il.schemaname = 'myschema'
    and il.indexrelname = 'myindex'
    and sa.sample_time >= now() - interval '24 hours'
    --and sa.sample_time between '2026-10-10 00:00:00.000 +0300' and '2026-10-19 23:00:00.000 +0300'
order by
    sa.sample_time desc,
    il.schemaname,
    il.indexrelname
--\gx