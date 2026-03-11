-- sessions by TEMP usage

with tmp_info as (
    select
        pg_tablespace_location(ts.oid) as tblspc_dir,
        ts.spcname as tblspc_name,
        sum(tmp.size) as tmp_size,
        count(*) as tmp_files,
        split_part(split_part(split_part(tmp.name, '_', 2), 'tmp', 2), '.', 1)::int as pid
    from
        pg_tablespace ts,
        pg_ls_tmpdir(ts.oid) tmp
    where
        ts.spcname <> 'pg_global'
    group by
        tblspc_dir, tblspc_name, pid
)
select
    --t.tblspc_dir,
    t.tblspc_name,
    pg_size_pretty(t.tmp_size) as tmp_size,
    t.tmp_files,
    t.pid,
    case
        when state = 'idle in transaction' then
                'done, duration: ' || round(abs(extract(epoch from (a.query_start - a.state_change))) * 1000) || ' ms'
        else
                'in progress, duration: ' || round(abs(extract(epoch from (clock_timestamp() - a.query_start))) * 1000) || ' ms'
    end as query_status,
    case
        when a.wait_event is null then 'CPU'
        else a.wait_event_type||':'||a.wait_event
    end wait_event,
    substr(a.state,1,25) AS state,
    substr(regexp_replace(regexp_replace(a.query, E'[\\n\\r]+', ' ', 'g'),  E'\\s+', ' ', 'g'),1,50) as short_query
from
    tmp_info t
    left join pg_stat_activity a on t.pid = a.pid
order by t.tmp_size desc;