-- sessions by state

select
    state,
    count(*) as sess_count,
    round(100.0 * count(*) / sum(count(*)) over (), 2) as pct,
    round(avg(extract(epoch from (clock_timestamp() - state_change)) * 1000)::numeric, 2) as avg_state_time_ms,
    round(min(extract(epoch from (clock_timestamp() - state_change)) * 1000)::numeric, 2) as min_state_time_ms,
    round(max(extract(epoch from (clock_timestamp() - state_change)) * 1000)::numeric, 2) as max_state_time_ms
from
    pg_stat_activity
where
    1 = 1
    and pid <> pg_backend_pid()
    and backend_type = 'client backend'
    --and state <> 'idle'
    --and wait_event <> 'ClientRead'
    --and application_name like 'psql%'
    --and pid = 123456
    --and client_addr = '192.168.1.1'
group by
    state
order by
    sess_count desc;