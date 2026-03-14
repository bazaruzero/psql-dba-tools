-- heavyweight locks for pid (EDIT script with your pid using \'e\' option)

-- https://postgres.ai/docs/postgres-howtos/performance-optimization/monitoring/how-to-analyze-heavyweight-locks-part-1

select
    l.pid,
    l.relation::regclass,
    l.locktype,
    --l.database,
    --l.page,
    --l.tuple,
    --l.virtualxid,
    --l.transactionid,
    --l.classid,
    --l.objid,
    --l.objsubid,
    --l.virtualtransaction,
    --l.pid,
    l.mode,
    l.granted,
    l.fastpath,
    --to_char(clock_timestamp() - a.xact_start,'HH24:MI:SS.MS') AS xact_start,
    --to_char(clock_timestamp() - a.query_start,'HH24:MI:SS.MS') AS query_start,
    --to_char(clock_timestamp() - a.state_change,'HH24:MI:SS.MS') AS state_change,
    case
    	when state = 'idle in transaction' then
       		'done, duration: ' || round(abs(extract(epoch from (a.query_start - a.state_change))) * 1000) || ' ms'
    	else
        	'in progress, duration: ' || round(abs(extract(epoch from (clock_timestamp() - a.query_start))) * 1000) || ' ms'
    end as query_status,
    case
        when a.wait_event is null then 'CPU'
        else a.wait_event_type||':'||wait_event
    end wait_event,
    substr(a.state,1,25) AS state,
    substr(regexp_replace(regexp_replace(a.query, E'[\\n\\r]+', ' ', 'g'),  E'\\s+', ' ', 'g'),1,50) AS short_query
from
    pg_stat_activity a
    join pg_locks l on a.pid = l.pid
    join pg_class c on l.relation = c.oid
where
    1 = 1
    and a.pid in (2064343)
    --and a.pid = pg_backend_pid()
    and l.locktype = 'relation'
    and l.relation::regclass::text !~ '^pg_';
    --and a.usename = 'myuser'
    --and a.application_name = 'psql'
    --and a.wait_event = 'LockManager'
;