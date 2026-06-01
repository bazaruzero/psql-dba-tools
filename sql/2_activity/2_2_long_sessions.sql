-- long runnning sessions (includes idle in transaction)

select
    --datname,
    usename,
    pid,
    --backend_type,
    --leader_pid,
    --backend_xid,
    --backend_xmin,
    --coalesce(backend_xid::text,'-') ||':'|| coalesce(backend_xmin::text,'-') as "xid:xmin",
    --substr(application_name, 1, 20) as app,
    --backend_start,
    age(clock_timestamp(), xact_start) as xact_duration,
    age(clock_timestamp(), query_start) as query_duration,
    age(clock_timestamp(), state_change) as state_duration,
    case
        when state = 'idle in transaction' then
            'done, duration: ' || round(abs(extract(epoch from (query_start - state_change))) * 1000) || ' ms'
        else
            'in progress, duration: ' || round(abs(extract(epoch from (clock_timestamp() - query_start))) * 1000) || ' ms'
    end as query_status,
    case
        when wait_event is null then 'CPU'
        else wait_event_type||':'||wait_event
    end wait_event,
    substr(state,1,25) as state,
    substr(regexp_replace(regexp_replace(query, E'[\\n\\r]+', ' ', 'g'), E'\\s+', ' ', 'g'),1,50) as short_query
from
    pg_stat_activity
where
    1=1
    and state <> 'idle'
    and pid <> pg_backend_pid()
    --and ((clock_timestamp() - query_start) > interval '1 seconds' or (clock_timestamp() - xact_start) > interval '1 seconds')
    --and backend_type = 'client backend'
    --and application_name like 'psql%'
    --and pid = 123
    --and client_addr = '192.168.1.1'
order by
    xact_duration desc
    --query_duration desc
;