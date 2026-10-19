-- growing tables for period (pg_profile required)

-- set search_path = XXX;

with period as (
    select
        now() - interval '1 days' as from_time,
        now() as to_time
        --'2026-10-01 00:00:00.000 +0300'::timestamptz as from_time,
        --'2026-10-02 00:00:00.000 +0300'::timestamptz as to_time
),
serv as (
    select s.server_id
    from servers s
    where
        s.enabled
        and s.server_name like (select split_part(pg_hostname(),'.',1) || '%')
),
tbl_growth as (
    select
        sst.server_id,
        sst.datid,
        sst.relid,
        count(*) as samples_cnt,
        sum(case when sst.relsize_diff > 0 then sst.relsize_diff else 0 end) as tbl_growth_bytes,
        min(sst.relsize) as tbl_min_size_bytes,
        max(sst.relsize) as tbl_max_size_bytes
    from
        samples sa
        join serv sv
            on sv.server_id = sa.server_id
        join sample_stat_tables sst
            on sst.sample_id = sa.sample_id and sst.server_id = sa.server_id
    cross join period p
    where
        sa.sample_time >= p.from_time
        and sa.sample_time <= p.to_time
    group by
        sst.server_id, sst.datid, sst.relid
    having
        sum(case when sst.relsize_diff > 0 then sst.relsize_diff else 0 end) > 0
)
select
    tl.schemaname as tbl_schema,
    substr(tl.relname,1,50) as tbl_name,
    tg.samples_cnt as samples_cnt,
    pg_size_pretty(tg.tbl_growth_bytes) as tbl_growth,
    pg_size_pretty(tg.tbl_min_size_bytes) as tbl_size_from,
    pg_size_pretty(tg.tbl_max_size_bytes) as tbl_size_to,
    round(100.0 * tg.tbl_growth_bytes / nullif(tg.tbl_max_size_bytes, 0), 1) as tbl_growth_pct
from
    tbl_growth tg
    join tables_list tl
        on tl.server_id = tg.server_id and tl.datid = tg.datid and tl.relid = tg.relid
order by
    tg.tbl_growth_bytes desc
limit 10
;