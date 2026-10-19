-- table stats history detailed (pg_profile required)

-- set search_path = XXX;

select
    sa.sample_time,
    --sst.datid,
    tl.schemaname as tbl_schema,
    substr(tl.relname,1,50) as tbl_name,
    --sst.*
--/*
    sst.n_live_tup as live_tup,
    sst.n_dead_tup as dead_tup,
    sst.n_tup_ins as tup_ins,
    sst.n_tup_upd as tup_upd,
    sst.n_tup_del as tup_del,
    sst.seq_scan,
    sst.idx_scan,
    sst.autovacuum_count as avac_cnt,
    sst.vacuum_count as vac_cnt,
    (sst.heap_blks_read + sst.heap_blks_hit) as heap_blks_read,
    (sst.idx_blks_read + sst.idx_blks_hit) as idx_blks_read,
    --(sst.toast_blks_read + sst.toast_blks_hit + sst.tidx_blks_read + sst.tidx_blks_hit) as toast_blks_read
    pg_size_pretty(sst.relsize_diff) as size_diff
--*/
from
    samples sa
    join sample_stat_tables sst
        on sa.sample_id = sst.sample_id and sa.server_id = sst.server_id
    join tables_list tl
        on tl.server_id=sst.server_id and tl.datid=sst.datid and tl.relid=sst.relid
where
    sa.server_id = (select server_id from servers s where s.enabled and s.server_name like (select split_part(pg_hostname(),'.',1) || '%'))
    and tl.relname='mytable'
    --and tl.schemaname = 'myschema'
    and sa.sample_time >= now() - interval '24 hours'
    --and sa.sample_time between '2026-10-10 00:00:00.000 +0300' and '2026-10-19 23:00:00.000 +0300'
order by
    sa.sample_time desc
--\gx