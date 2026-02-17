-- long runnning sessions (includes idle in transaction)

select
    pid,
    --datname,
    usename,
    --backend_type,
    --leader_pid,
    --backend_xid,
    --backend_xmin,
    --coalesce(backend_xid::text,'-') ||':'|| coalesce(backend_xmin::text,'-') as "xid:xmin",
    --substr(application_name, 1, 20) AS app,
    --backend_start,
    to_char(clock_timestamp() - xact_start,'HH24:MI:SS.MS') AS xact_start,
    to_char(clock_timestamp() - query_start,'HH24:MI:SS.MS') AS query_start,
    to_char(clock_timestamp() - state_change,'HH24:MI:SS.MS') AS state_change,
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
    substr(state,1,25) AS state,
    substr(regexp_replace(regexp_replace(query, E'[\\n\\r]+', ' ', 'g'),  E'\\s+', ' ', 'g'),1,50) AS short_query
from
    pg_stat_activity
where 1=1
    and state <> 'idle' 
    and pid <> pg_backend_pid()
    and ( (clock_timestamp() - query_start) > interval '5 seconds' OR (clock_timestamp() - xact_start) > interval '5 seconds')
    --and backend_type = 'client backend'
    --and application_name like 'psql%'
    --and pid = 123
    --and client_addr = '192.168.1.1'
order by
    xact_start desc;