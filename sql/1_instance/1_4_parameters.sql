-- parameters (basic)

select
    name,
    setting as curr_value,
    unit,
    case
        when name = 'autovacuum' then 'on'
        when name = 'autovacuum_max_workers' then '3'
        when name = 'bgwriter_delay' then '50ms / 10ms'
        when name = 'bgwriter_lru_maxpages' then '300 / 1000'
        when name = 'checkpoint_completion_target' then '0.9'
        when name = 'checkpoint_timeout' then '900s'
        when name = 'fastpath_num_locks' then '-'
        when name = 'log2_num_lock_partitions' then '-'
        when name = 'max_wal_size' then '-'
        when name = 'plan_cache_mode' then 'force_custom_plan'
        when name = 'synchronous_commit' then 'on'
        when name = 'wal_compression' then 'on / lz4'
        when name = 'wal_sync_method' then 'fdatasync'
        when name = 'shared_buffers' then '25-50% RAM'
        when name = 'effective_cache_size' then '75% RAM'
        when name = 'huge_pages' then 'on'
        when name = 'max_parallel_workers_per_gather' then '0'
        when name = 'max_parallel_maintenance_workers' then '-'
        when name = 'max_parallel_workers' then '-'
        when name = 'max_worker_processes' then '-'
        when name = 'track_io_timing' then 'on'
        when name = 'autovacuum_timeout_threshold_enable' then 'on'
        when name = 'max_connections' then '300 (use connection pool)'
        when name = 'work_mem' then '-'
        when name = 'maintenance_work_mem' then '-'
        when name = 'effective_io_concurrency' then 'concurrent IO only really activated if OS supports posix_fadvise function'
        when name = 'wal_level' then '-'
        when name = 'max_wal_senders' then '-'
        when name = 'min_wal_size' then '-'
        when name = 'wal_keep_size' then '-'
        when name = 'jit' then 'off'
        else '-'
    end as recom_value
from 
    pg_settings
where
    name in ('autovacuum',
    'autovacuum_max_workers',
    'bgwriter_delay',
    'bgwriter_lru_maxpages',
    'checkpoint_completion_target',
    'checkpoint_timeout',
    'fastpath_num_locks',
    'log2_num_lock_partitions',
    'max_wal_size',
    'plan_cache_mode',
    'synchronous_commit',
    'wal_compression',
    'wal_sync_method',
    'shared_buffers',
    'effective_cache_size',
    'huge_pages',
    'max_parallel_workers_per_gather',
    'max_parallel_maintenance_workers',
    'max_parallel_workers',
    'max_worker_processes',
    'track_io_timing',
    'autovacuum_timeout_threshold_enable',
    'max_connections',
    'work_mem',
    'maintenance_work_mem',
    'effective_io_concurrency',
    'wal_level',
    'min_wal_size',
    'wal_keep_size',
    'jit')
order by name;