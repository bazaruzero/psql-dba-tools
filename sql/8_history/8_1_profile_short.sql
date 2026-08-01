-- sql history stats short (pg_profile required)

-- set search_path = XXX;

select 
    s.sample_time,
    ss.calls,
    ss.queryid, ss.queryid_md5,
    --substr(sl.query,1,100) AS short_query,
    substr(regexp_replace(regexp_replace(sl.query, E'[\\n\\r]+', ' ', 'g'), E'\\s+', ' ', 'g'), 1, 100) as short_query
    /*
    round(ss.mean_exec_time::numeric, 2) as avg_exec_ms,
    round(ss.min_exec_time::numeric, 2) as min_exec_ms,
    round(ss.max_exec_time::numeric, 2) as max_exec_ms,
    ss.plans,
    round(ss.mean_plan_time::numeric, 2) as avg_plan_ms,
    round(ss.min_plan_time::numeric, 2) as min_plan_ms,
    round(ss.max_plan_time::numeric, 2) as max_plan_ms,
    ss.rows,
    case
        when ss.calls <> 0 then round((ss.rows / ss.calls)::numeric, 2)
        else null
    end rows_per_call,
    ss.shared_blks_hit,
    ss.shared_blks_read,
    case
        when ss.calls <> 0 then round((ss.shared_blks_hit / ss.calls)::numeric, 2)
        else null
    end blks_hit_per_call,
    case
        when ss.calls <> 0 then round((ss.shared_blks_read / ss.calls)::numeric, 2)
        else null
    end blks_read_per_call
    */
from
    samples s,
    sample_statements ss,
    stmt_list sl
where
    s.sample_id = ss.sample_id
    and s.server_id = ss.server_id
    and s.server_id = sl.server_id
    and ss.queryid_md5 = sl.queryid_md5
    and s.server_id = (select server_id from servers s where s.enabled and s.server_name like (select split_part(pg_hostname(),'.',1) || '%'))
    and s.sample_time >= now() - interval '24 hours'
    and ss.queryid = '-5165019744091131251'
    --and ss.queryid_md5 = 'G0C7FXTEAEgqLsuBVhENz9ZgWOfl3wtx'
    --and lower(sl.query) like lower('%select%')
order by s.sample_time;
