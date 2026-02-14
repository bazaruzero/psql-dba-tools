-- uptime

select
    date_trunc('second', current_timestamp - pg_postmaster_start_time()) as uptime,
    pg_postmaster_start_time() as start_time
;