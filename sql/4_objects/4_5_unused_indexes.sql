-- unused indexes

--
-- https://postgres.ai/docs/postgres-howtos/performance-optimization/indexing/how-to-find-unused-indexes
--

------
select
    now() as check_date,
    --pg_hostname() as pg_host,
    datname,
    coalesce(stats_reset, pg_postmaster_start_time()) as stats_or_start_time,
    age(now(), coalesce(stats_reset, pg_postmaster_start_time())) as age_since_reset_or_start
from pg_stat_database
where datname = current_database();

------
select
    s.schemaname,
    s.relname as table_name,
    s.indexrelname as index_name,
    s.idx_scan,
    i.indisunique,
    pg_size_pretty(pg_relation_size(s.indexrelid)) as index_size
from pg_stat_user_indexes s
join pg_index i on i.indexrelid = s.indexrelid
where
    s.idx_scan = 0
    and not i.indisunique
order by pg_relation_size(s.indexrelid) desc;

------
select
    coalesce(pg_size_pretty(sum(pg_relation_size(s.indexrelid))), '0 bytes') as total_unused_idx_size
from pg_stat_user_indexes s
join pg_index i on i.indexrelid = s.indexrelid
where
    s.idx_scan = 0
    and not i.indisunique;