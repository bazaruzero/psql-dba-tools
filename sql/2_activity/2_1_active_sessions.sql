-- active sessions

select
    --datname,
    usename,
    pid,
    backend_type,
    --leader_pid,
    --backend_xid,
    --backend_xmin,
    substr(application_name, 1, 20) AS app,
    --backend_start,
    to_char(clock_timestamp() - xact_start,'DD HH24:MI:SS.MS') AS xact_start,
    to_char(clock_timestamp() - query_start,'DD HH24:MI:SS.MS') AS query_start,
    to_char(clock_timestamp() - state_change,'DD HH24:MI:SS.MS') AS state_change,
    case
        when wait_event is null then 'CPU'
        else wait_event_type||':'||wait_event
    end wait_event,
    substr(state,1,25) AS state,
    substr(regexp_replace(regexp_replace(query, E'[\\n\\r]+', ' ', 'g'),  E'\\s+', ' ', 'g'),1,40) AS short_query
from
    pg_stat_activity
where 1=1
    and state <> 'idle' 
    and pid <> pg_backend_pid()
    --and backend_type = 'client backend'
    --and application_name like 'psql%'
    --and pid = 123
    --and client_addr = '192.168.1.1'
order by
    xact_start desc;