-- wait events

select
    case
        when wait_event is null then 'CPU'
        else wait_event_type||':'||wait_event
    end wait_events,
    count(*) as sess_count,
    round(100.0 * count(*) / sum(count(*)) over ()) as pct_wait_events
from
    pg_stat_activity
where
    1 = 1
    and state <> 'idle'
    and pid <> pg_backend_pid()
    --and wait_event <> 'ClientRead'
    --and backend_type = 'client backend'
    --and application_name like 'psql%'
    --and pid = 123456
    --and client_addr = '192.168.1.1'
group by
    wait_events
order by
    sess_count desc;