-- recovery role
select
    case
        when pg_is_in_recovery() then 'Replica [read only]'
        else 'Master [read-write]'
    end as role,
    (select setting from pg_settings where name = 'synchronous_commit') as synchronous_commit,
    (select setting from pg_settings where name = 'synchronous_standby_names') as synchronous_standby_names,
    (select setting from pg_settings where name = 'hot_standby') as hot_standby,
    (select setting from pg_settings where name = 'hot_standby_feedback') as hot_standby_feedback,
    (select setting ||' '|| unit from pg_settings where name = 'recovery_min_apply_delay') as recovery_min_apply_delay,
    (select setting ||' '|| unit from pg_settings where name = 'wal_keep_size') as wal_keep_size
;