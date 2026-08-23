-- table stats history detailed (pg_profile required)

-- set search_path = XXX;

select
    sa.sample_time,
    --sst.datid,
    --tl.schemaname,
    substr(tl.relname,1,50) relname,
    --sst.*
--/*
    sst.n_live_tup,
    sst.n_dead_tup,
    sst.n_tup_ins,
    sst.n_tup_upd,
    sst.n_tup_del,
    sst.seq_scan,
    sst.idx_scan,
    sst.autovacuum_count,
    sst.vacuum_count
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
    and tl.schemaname = 'myschema'
    and sa.sample_time >= now() - interval '24 hours'
    --and sa.sample_time between '2026-08-19 00:00:00.000 +0300' and '2026-08-19 23:00:00.000 +0300'
order by
    sa.sample_time desc
--\gx