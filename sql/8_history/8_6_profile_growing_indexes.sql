-- growing indexes for period (pg_profile required)

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
idx_growth as (
    select
        ssi.server_id,
        ssi.datid,
        ssi.indexrelid,
        count(*) as samples_cnt,
        sum(case when ssi.relsize_diff > 0 then ssi.relsize_diff else 0 end) as idx_growth_bytes,
        min(ssi.relsize) as idx_min_size_bytes,
        max(ssi.relsize) as idx_max_size_bytes
    from
        samples sa
        join serv sv
            on sv.server_id = sa.server_id
        join sample_stat_indexes ssi
            on ssi.sample_id = sa.sample_id and ssi.server_id = sa.server_id
    cross join period p
    where
        sa.sample_time >= p.from_time
        and sa.sample_time <= p.to_time
    group by
        ssi.server_id, ssi.datid, ssi.indexrelid
    having
        sum(case when ssi.relsize_diff > 0 then ssi.relsize_diff else 0 end) > 0
)
select
    il.schemaname as idx_schema,
    substr(il.indexrelname,1,50) as idx_name,
    ig.samples_cnt as samples_cnt,
    pg_size_pretty(ig.idx_growth_bytes) as idx_growth,
    pg_size_pretty(ig.idx_min_size_bytes) as idx_size_from,
    pg_size_pretty(ig.idx_max_size_bytes) as idx_size_to,
    round(100.0 * ig.idx_growth_bytes / nullif(ig.idx_max_size_bytes, 0), 1) as idx_growth_pct
from
    idx_growth ig
    join indexes_list il
        on il.server_id = ig.server_id and il.datid = ig.datid and il.indexrelid = ig.indexrelid
order by
    ig.idx_growth_bytes desc
limit 10
;