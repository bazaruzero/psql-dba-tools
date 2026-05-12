-- replication lag

--
--  ===== Docs =====
--
--   https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-REPLICATION-VIEW
--   https://www.postgresql.org/docs/current/view-pg-replication-slots.html
--
-- ===== Physical =====
--
--           _____replay_lag____    _____flush_lag____  _____write_lag___  __pending_lag__
-- wal      |                  |   |                 | |                | |               |
-- --------replay_lsn----------flush_lsn----------write_lsn----------sent_lsn----------current_lsn---------->
--           |                                                                             |
--           |_____________________________________total_lag_______________________________|
--           
-- ===== Logical =====
--
-- wal
-- --------restart_lsn---------------------------confirmed_flush_lsn-------------------current_lsn---------->
--           |                                                                             |
--           |_____________________________________total_lag_______________________________|
--
--
-- ===== Replication lag diagnostics for logical replication slots =====
--
-- 1) If restart_lsn_lag is significantly larger than confirmed_flush_lsn_lag:
--      Likely a long-running transaction that hasn't been committed yet.
--      Meanwhile, other small transaction changes are being applied normally,
--      as confirmed_flush_lsn_lag remains relatively low compared to restart_lsn_lag.
--
-- 2) If both restart_lsn_lag and confirmed_flush_lsn_lag are large and close to each other:
--      Possible causes:
--        - Replica is unable to keep up with receiving changes (replay lag)
--        - The process consuming the replication slot is failing (e.g., walsender crashes with
--          "ERROR: out of memory | Cannot enlarge string buffer containing 1073741822 bytes by 1 more bytes"),
--          causing WAL accumulation.
--

select
    coalesce(r.pid, rs.active_pid) as pid,
    r.client_addr,
    r.usename as user,
    a.backend_type,
    a.backend_start,
    date_trunc('second', current_timestamp - a.backend_start) as backend_uptime,
    case when a.wait_event is null then 'CPU' else a.wait_event_type||':'||a.wait_event end as wait_event,
    substr(a.state,1,25) as sess_state,
    coalesce(r.application_name, rs.slot_name) as app_name,
    r.state as repl_state,
    r.sync_state as mode,
    rs.slot_name,
    rs.plugin,
    rs.slot_type,
    rs.database ||'('|| rs.datoid ||')' as database,
    rs.active as is_active,
    rs.temporary as is_temp,
    rs.xmin,
    age(rs.xmin) as xmin_age,
    rs.catalog_xmin,
    age(rs.catalog_xmin) as catalog_xmin_age,
    rs.restart_lsn,
    rs.confirmed_flush_lsn,
    pg_size_pretty(pg_wal_lsn_diff(r.flush_lsn, r.replay_lsn)) as replay_lag,
    pg_size_pretty(pg_wal_lsn_diff(r.write_lsn, r.flush_lsn)) as flush_lag,
    pg_size_pretty(pg_wal_lsn_diff(r.sent_lsn, r.write_lsn)) as write_lag,
    pg_size_pretty(pg_wal_lsn_diff(case when pg_is_in_recovery() then pg_last_wal_replay_lsn() else pg_current_wal_lsn() end, r.sent_lsn)) as pending_lag,
    pg_size_pretty(pg_wal_lsn_diff(case when pg_is_in_recovery() then pg_last_wal_replay_lsn() else pg_current_wal_lsn() end, rs.restart_lsn)) as restart_lsn_lag,
    pg_size_pretty(pg_wal_lsn_diff(case when pg_is_in_recovery() then pg_last_wal_replay_lsn() else pg_current_wal_lsn() end, rs.confirmed_flush_lsn)) as confirmed_flush_lsn_lag,
    coalesce(pg_size_pretty(pg_wal_lsn_diff(case when pg_is_in_recovery() then pg_last_wal_replay_lsn() else pg_current_wal_lsn() end, r.replay_lsn)), 
             pg_size_pretty(pg_wal_lsn_diff(case when pg_is_in_recovery() then pg_last_wal_replay_lsn() else pg_current_wal_lsn() end, rs.restart_lsn))) as total_lag
from
    pg_replication_slots rs
    full outer join pg_stat_replication r on rs.active_pid = r.pid
    left join pg_stat_activity a on coalesce(r.pid, rs.active_pid) = a.pid
where 
    rs.slot_name is not null 
    or r.pid is not null
order by 
    total_lag desc nulls last
\gx