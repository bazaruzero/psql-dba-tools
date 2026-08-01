-- sql history stats detailed (pg_profile required)

-- set search_path = XXX;

with sample_agg as (
    select
        s.server_id,
        s.sample_id,
        s.sample_time,
        ss.queryid,
        ss.queryid_md5,
        sum(ss.calls)                          as calls,
        sum(ss.rows)                           as rows,
        sum(ss.total_plan_time)                as total_plan_time,
        sum(ss.total_exec_time)                as total_exec_time,
        sum(ss.shared_blk_read_time)           as shared_blk_read_time,
        sum(ss.shared_blk_write_time)          as shared_blk_write_time,
        sum(ss.wal_bytes)                      as wal_bytes,
        sum(ss.shared_blks_hit)                as shared_blks_hit,
        sum(ss.shared_blks_read)               as shared_blks_read,
        sum(ss.shared_blks_dirtied)            as shared_blks_dirtied,
        sum(ss.shared_blks_written)            as shared_blks_written,
        sum(ss.local_blks_hit)                 as local_blks_hit,
        sum(ss.local_blks_read)                as local_blks_read,
        sum(ss.local_blks_dirtied)             as local_blks_dirtied,
        sum(ss.local_blks_written)             as local_blks_written,
        sum(ss.temp_blks_read)                 as temp_blks_read,
        sum(ss.temp_blks_written)              as temp_blks_written,
        sum(ss.calls * ss.mean_exec_time) / nullif(sum(ss.calls), 0) as mean_exec_time
    from
        samples s
        join sample_statements ss
            on s.sample_id = ss.sample_id and s.server_id = ss.server_id
    group by s.server_id, s.sample_id, s.sample_time, ss.queryid, ss.queryid_md5
),
-- Total metrics per sample_id (across ALL queryid, no filter)
sample_totals as (
    select
        sample_id,
        sum(total_plan_time + total_exec_time)    as tot_db_time,
        sum(total_plan_time + total_exec_time
            - shared_blk_read_time - shared_blk_write_time) as tot_cpu_time,
        sum(shared_blk_read_time + shared_blk_write_time) as tot_io_time,
        sum(calls)                                as tot_calls,
        sum(wal_bytes)                            as tot_wal_bytes
    from sample_agg
    group by sample_id
),
stmt_text as (
    select distinct on (server_id, queryid_md5)
        server_id, queryid_md5, query
    from stmt_list
    order by server_id, queryid_md5, last_sample_id desc
)
select
    sa.sample_time,
    sa.queryid,
    sa.queryid_md5,
    substr(regexp_replace(regexp_replace(stx.query, E'[\\n\\r]+', ' ', 'g'), E'\\s+', ' ', 'g'), 1, 100) as short_query,
    sa.calls::bigint as calls,
    sa.rows::bigint as rows,
    case when sa.calls <> 0 then round((sa.rows::numeric / sa.calls), 2) else null end rows_per_call,

    -- DB time share and total
    case
        when round(
            ((sa.total_plan_time + sa.total_exec_time)::numeric
             / nullif(st.tot_db_time::numeric, 0)
            ) * 100, 2
        ) is null then 0
        else round(
            ((sa.total_plan_time + sa.total_exec_time)::numeric
             / nullif(st.tot_db_time::numeric, 0)
            ) * 100, 2
        )
    end "t_db_time_%",
    round((sa.total_plan_time + sa.total_exec_time)::numeric, 2) as t_db_time_ms,

    -- CPU time (total minus I/O wait)
    case
        when round(
            ((sa.total_plan_time + sa.total_exec_time
              - sa.shared_blk_read_time - sa.shared_blk_write_time)::numeric
             / nullif(st.tot_cpu_time::numeric, 0)
            ) * 100, 2
        ) is null then 0
        else round(
            ((sa.total_plan_time + sa.total_exec_time
              - sa.shared_blk_read_time - sa.shared_blk_write_time)::numeric
             / nullif(st.tot_cpu_time::numeric, 0)
            ) * 100, 2
        )
    end "t_cpu_%",
    round((sa.total_plan_time + sa.total_exec_time
           - sa.shared_blk_read_time - sa.shared_blk_write_time)::numeric, 2)
        as t_cpu_time_ms,

    -- I/O time share and total
    case
        when round(
            ((sa.shared_blk_read_time + sa.shared_blk_write_time)::numeric
             / nullif(st.tot_io_time::numeric, 0)
            ) * 100, 2
        ) is null then 0
        else round(
            ((sa.shared_blk_read_time + sa.shared_blk_write_time)::numeric
             / nullif(st.tot_io_time::numeric, 0)
            ) * 100, 2
        )
    end "t_io_%",
    round((sa.shared_blk_read_time + sa.shared_blk_write_time)::numeric, 2)
        as t_io_time_ms,

    -- Calls share and total
    case
        when round(
            (sa.calls::numeric / nullif(st.tot_calls::numeric, 0)) * 100, 2
        ) is null then 0
        else round(
            (sa.calls::numeric / nullif(st.tot_calls::numeric, 0)) * 100, 2
        )
    end "t_calls_%",
    sa.calls as t_calls,

    -- WAL size share and pretty
    case
        when round(
            (sa.wal_bytes::numeric / nullif(st.tot_wal_bytes::numeric, 0)) * 100, 2
        ) is null then 0
        else round(
            (sa.wal_bytes::numeric / nullif(st.tot_wal_bytes::numeric, 0)) * 100, 2
        )
    end "t_wal_size_%",
    pg_size_pretty(sum(sa.wal_bytes) over (partition by sa.sample_id))
        as t_wal_size,

    -- Mean exec time from the sample
    round(sa.mean_exec_time::numeric, 3) as avg_exec_time_ms,

    -- Shared blocks - total and per call
    sa.shared_blks_hit::bigint as shared_blks_hit,
    case when sa.calls <> 0 then round((sa.shared_blks_hit::numeric / sa.calls), 2) else null end shared_blks_hit_per_call,
    sa.shared_blks_read::bigint as shared_blks_read,
    case when sa.calls <> 0 then round((sa.shared_blks_read::numeric / sa.calls), 2) else null end shared_blks_read_per_call,
    sa.shared_blks_dirtied::bigint as shared_blks_dirtied,
    case when sa.calls <> 0 then round((sa.shared_blks_dirtied::numeric / sa.calls), 2) else null end shared_blks_dirtied_per_call,
    sa.shared_blks_written::bigint as shared_blks_written,
    case when sa.calls <> 0 then round((sa.shared_blks_written::numeric / sa.calls), 2) else null end shared_blks_written_per_call,

    -- Local blocks - total and per call
    sa.local_blks_hit::bigint as local_blks_hit,
    case when sa.calls <> 0 then round((sa.local_blks_hit::numeric / sa.calls), 2) else null end local_blks_hit_per_call,
    sa.local_blks_read::bigint as local_blks_read,
    case when sa.calls <> 0 then round((sa.local_blks_read::numeric / sa.calls), 2) else null end local_blks_read_per_call,
    sa.local_blks_dirtied::bigint as local_blks_dirtied,
    case when sa.calls <> 0 then round((sa.local_blks_dirtied::numeric / sa.calls), 2) else null end local_blks_dirtied_per_call,
    sa.local_blks_written::bigint as local_blks_written,
    case when sa.calls <> 0 then round((sa.local_blks_written::numeric / sa.calls), 2) else null end local_blks_written_per_call,

    -- Temp blocks - total and per call
    sa.temp_blks_read::bigint as temp_blks_read,
    case when sa.calls <> 0 then round((sa.temp_blks_read::numeric / sa.calls), 2) else null end temp_blks_read_per_call,
    sa.temp_blks_written::bigint as temp_blks_written,
    case when sa.calls <> 0 then round((sa.temp_blks_written::numeric / sa.calls), 2) else null end temp_blks_written_per_call

from
    sample_agg sa
    join sample_totals st
        on sa.sample_id = st.sample_id
    left join stmt_text stx
        on sa.server_id = stx.server_id
       and sa.queryid_md5 = stx.queryid_md5
where
    sa.server_id = (select server_id from servers s where s.enabled and s.server_name like (select split_part(pg_hostname(),'.',1) || '%'))
    --and sa.sample_time >= now() - interval '24 hours'
    --and sa.sample_time between '2026-07-31 11:00:00.000 +0300' and '2026-07-31 12:00:00.000 +0300'
    --and sa.queryid = '8130492525423832630'
    --and sa.queryid_md5 = 'G0C7FXTEAEgqLsuBVhENz9ZgWOfl3wtx'
--order by sa.sample_time, (sa.total_plan_time + sa.total_exec_time) desc
order by t_db_time_ms desc
limit 10
\gx
