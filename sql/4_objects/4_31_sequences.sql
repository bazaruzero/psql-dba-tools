-- sequences

with seq_data as (
    select
        s.schemaname as seq_schema,
        s.sequencename as seq_name,
        s.data_type,
        s.start_value,
        s.min_value,
        s.max_value,
        s.increment_by,
        s.cycle as is_cycle,
        s.cache_size,
        s.last_value,
        -- how far the sequence's lifecycle has progressed (0-100%)
        -- NULL last_value means the sequence has never been used
        case
            when s.last_value is null then 0
            when sign(s.increment_by) >= 0
                then (s.last_value::numeric - s.min_value)
                     / nullif(s.max_value::numeric - s.min_value, 0) * 100
            -- descending sequence moves from max_value down to min_value
            else (s.min_value::numeric - s.last_value)
                 / nullif(s.min_value::numeric - s.max_value, 0) * 100
        end as utilization_pct
    from
        pg_sequences s
)
select
    seq_schema,
    seq_name,
    data_type,
    start_value,
    min_value,
    max_value,
    increment_by,
    is_cycle,
    cache_size,
    last_value,
    round(utilization_pct::numeric, 2) as util_pct
from
    seq_data
order by
    round(utilization_pct::numeric, 2) desc,
    last_value desc
    nulls last
--limit 10
;