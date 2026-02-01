-- sessions activity
select count(1) as active_sess_count from pg_stat_activity where state = 'active';