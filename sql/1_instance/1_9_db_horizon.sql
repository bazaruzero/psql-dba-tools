-- database horizon
--
-- Ref. to https://pganalyze.com/docs/checks/vacuum/xmin_horizon
--         https://habr.com/ru/articles/890044/
--
-- Common Causes of Database Horizon Hold:
--
--- Long-running transactions
--- Lagging or stale physical replication slots
--- Lagging or stale logical replication slots
--- Long-running queries on Standby
--- Abandoned prepared transactions
--

\echo ''
\echo '########## Global ##########'
\echo ''

select coalesce(
    greatest(
        (select max(age(backend_xmin)) from pg_stat_activity where backend_xmin is not null),
        (select max(age(backend_xid)) from pg_stat_activity where backend_xid is not null),
        (select max(age(xmin)) from pg_replication_slots where xmin is not null),
        (select max(age(catalog_xmin)) from pg_replication_slots where catalog_xmin is not null),
        (select max(age(transaction)) from pg_prepared_xacts)
    ), 0
) as max_xmin_age;

\echo ''
\echo '########## Details ##########'
\echo ''

\echo ''
\echo '##### Sessions #####'
\echo ''

select 
    datname as db,
    usename as user,
    pid, 
    backend_xmin as xmin, -- snapshot
    age(backend_xmin) as xmin_age, -- snapshot age
    backend_xid as xid, -- session real transaction id
    age(backend_xid) as xid_age, -- session real transaction id age
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
    substr(state,1,25) as state
from 
    pg_stat_activity 
where 
    1 = 1
    and (backend_xmin is not null OR backend_xid is not null)
    and pid <> pg_backend_pid()
order by greatest(age(backend_xmin), age(backend_xid)) desc;

\echo ''
\echo '##### Lagging Replication Slots (physical/logical) #####'
\echo ''

\echo '... Check "Replication" section for a lag ...'

\echo ''
\echo '##### Long-running queries on Physical Standby (hot_standby_feedback = on) #####'
\echo ''

select max(age(xmin)) as xmin_age from pg_replication_slots where xmin is not null;

select max(age(catalog_xmin)) as catalog_xmin_age from pg_replication_slots where catalog_xmin is not null;

\echo ''
\echo '##### Abandoned prepared transactions #####'
\echo ''

select 
    gid,
    prepared,
    owner,
    database,
    transaction AS xmin,
    age(transaction) AS xmin_age
from
    pg_prepared_xacts
order by age(transaction) desc;