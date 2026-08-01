-- check objects in cache (pg_buffercache required)

with buffer_stats as (
    select 
        c.relname,
        count(*) as buffers,
        count(*) * current_setting('block_size')::int as size_bytes,
        round(count(*) * current_setting('block_size')::int / 1024.0 / 1024.0, 2) as size_mb
    from 
        pg_buffercache b
    join 
        pg_class c on b.relfilenode = pg_relation_filenode(c.oid)
    where 
        b.relfilenode != 0
    group by 
        c.relname
),
total_stats as (
    select 
        sum(buffers) as total_buffers,
        sum(size_bytes) as total_size_bytes
    from 
        buffer_stats
)
select 
    bs.relname,
    bs.buffers,
    bs.size_mb,
    round(bs.buffers * 100.0 / ts.total_buffers, 2) as pct_total_buffers,
    round(bs.size_bytes * 100.0 / ts.total_size_bytes, 2) as pct_total_size
from 
    buffer_stats bs,
    total_stats ts
--where
    --bs.relname like 'test%'
    --bs.relname like 'payment%'
order by 
    bs.buffers desc
limit 10;
